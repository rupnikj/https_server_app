import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show rootBundle, Clipboard, ClipboardData;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'dart:developer' as developer; // For logging

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter HTTPS Server',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const ServerPage(),
    );
  }
}

class ServerPage extends StatefulWidget {
  const ServerPage({super.key});

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  HttpServer? _server;
  String _serverAddress = 'Not running';
  final int _port = 8443; // Port for HTTPS

  // Store selected HTML files
  List<File> _selectedFiles = [];
  Map<String, String> _fileContents = {}; // Cache file contents

  // Handler function for serving content
  Future<shelf.Response> _handleRequest(shelf.Request request) async {
    final requestPath = request.url.path;

    if (requestPath == '' || requestPath == '/') {
      // Serve a simple index page listing available files
      final availableFiles =
          _selectedFiles.map((f) => path.basename(f.path)).toList();
      final htmlContent = _generateIndexPage(availableFiles);
      return shelf.Response.ok(
        htmlContent,
        headers: {'content-type': 'text/html'},
      );
    }

    // Check if requesting a selected HTML file
    final encodedFileName =
        requestPath.startsWith('/') ? requestPath.substring(1) : requestPath;
    // URL decode the filename to handle spaces and special characters
    final fileName = Uri.decodeComponent(encodedFileName);

    final file = _selectedFiles.firstWhere(
      (f) => path.basename(f.path) == fileName,
      orElse: () => File(''),
    );

    if (file.path.isNotEmpty && await file.exists()) {
      try {
        // Get cached content or read from file
        String content;
        if (_fileContents.containsKey(fileName)) {
          content = _fileContents[fileName]!;
        } else {
          content = await file.readAsString();
          _fileContents[fileName] = content; // Cache it
        }

        return shelf.Response.ok(
          content,
          headers: {'content-type': 'text/html'},
        );
      } catch (e) {
        developer.log('Error reading file $fileName: $e', name: 'HttpServer');
        return shelf.Response.internalServerError(body: 'Error reading file');
      }
    }

    // For other requests, return 404
    return shelf.Response.notFound('Not found');
  }

  String _generateIndexPage(List<String> fileNames) {
    final fileLinks = fileNames
        .map((name) {
          // URL encode the filename to handle spaces and special characters
          final encodedName = Uri.encodeComponent(name);
          return '<li><a href="/$encodedName">$name</a></li>';
        })
        .join('\n        ');

    return '''
<!DOCTYPE html>
<html>
<head>
    <title>Flutter HTTPS Server</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        h1 { color: #2196F3; }
        ul { list-style-type: none; padding: 0; }
        li { margin: 10px 0; }
        a { text-decoration: none; color: #1976D2; font-size: 18px; }
        a:hover { text-decoration: underline; }
        .no-files { color: #666; font-style: italic; }
    </style>
</head>
<body>
    <h1>Available HTML Files</h1>
    ${fileNames.isEmpty ? '<p class="no-files">No HTML files have been selected yet. Use the app to add some files!</p>' : '<ul>$fileLinks</ul>'}
</body>
</html>''';
  }

  Future<void> _pickHtmlFiles() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['html', 'htm'],
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final newFiles =
            result.paths
                .where((path) => path != null)
                .map((path) => File(path!))
                .where(
                  (file) =>
                      !_selectedFiles.any(
                        (existing) => existing.path == file.path,
                      ),
                )
                .toList();

        if (newFiles.isNotEmpty) {
          setState(() {
            _selectedFiles.addAll(newFiles);
          });

          // Pre-load file contents
          for (final file in newFiles) {
            try {
              final content = await file.readAsString();
              _fileContents[path.basename(file.path)] = content;
            } catch (e) {
              developer.log(
                'Error pre-loading file ${file.path}: $e',
                name: 'HttpServer',
              );
            }
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Added ${newFiles.length} HTML file(s)'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Files already selected or no valid files found'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking files: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _removeFile(int index) {
    setState(() {
      final fileName = path.basename(_selectedFiles[index].path);
      _fileContents.remove(fileName);
      _selectedFiles.removeAt(index);
    });
  }

  void _clearAllFiles() {
    setState(() {
      _selectedFiles.clear();
      _fileContents.clear();
    });
  }

  Future<void> _startServer() async {
    if (_server != null) {
      setState(() {
        _serverAddress = 'Server already running on $_serverAddress';
      });
      return;
    }

    try {
      // Load SSL certificate and key
      final certificateChain = await rootBundle.loadString('assets/server.crt');
      final serverKey = await rootBundle.loadString('assets/server.key');

      // Create a security context
      final securityContext =
          SecurityContext()
            ..useCertificateChainBytes(certificateChain.codeUnits)
            ..usePrivateKeyBytes(serverKey.codeUnits);

      final pipeline = const shelf.Pipeline()
          .addMiddleware(shelf.logRequests())
          .addHandler(_handleRequest);

      // Find a suitable IP address
      String? ipAddress;
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: true,
      );

      if (interfaces.isNotEmpty) {
        // Prefer non-loopback addresses
        final nonLoopback = interfaces.firstWhere(
          (iface) => iface.addresses.any((addr) => addr.address != '127.0.0.1'),
          orElse:
              () =>
                  interfaces
                      .first, // Fallback to the first one if no non-loopback
        );
        if (nonLoopback.addresses.isNotEmpty) {
          ipAddress = nonLoopback.addresses.first.address;
        }
      }
      ipAddress ??= '127.0.0.1'; // Default if no IP found

      // DEAD code is not a problem, just for temporary testing
      const bool useHttps = false;
      _server = await shelf_io.serve(
        pipeline,
        useHttps ? ipAddress : '127.0.0.1',
        useHttps ? _port : 8080,
        securityContext: useHttps ? securityContext : null,
      );

      final scheme = useHttps ? 'https' : 'http';
      setState(() {
        _serverAddress =
            'Running on $scheme://${_server!.address.host}:${_server!.port}';
        developer.log('Server started: $_serverAddress', name: 'HttpServer');
      });
    } catch (e, s) {
      setState(() {
        _serverAddress = 'Error starting server: $e';
      });
      developer.log(
        'Error starting server',
        error: e,
        stackTrace: s,
        name: 'HttpServer',
      );
    }
  }

  Future<void> _stopServer() async {
    if (_server != null) {
      await _server!.close(force: true);
      setState(() {
        _server = null;
        _serverAddress = 'Server stopped.';
        developer.log('Server stopped', name: 'HttpServer');
      });
    } else {
      setState(() {
        _serverAddress = 'Server is not running.';
      });
    }
  }

  @override
  void dispose() {
    _stopServer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flutter HTTPS Server')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Server Status Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              _serverAddress,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (_server != null) ...[
                            IconButton(
                              icon: const Icon(Icons.copy),
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text: _serverAddress.split(' on ')[1],
                                  ),
                                );
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Server URL copied to clipboard!',
                                      ),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                              tooltip: 'Copy server URL',
                            ),
                            IconButton(
                              icon: const Icon(Icons.open_in_browser),
                              onPressed: () async {
                                final url = _serverAddress.split(' on ')[1];
                                try {
                                  final uri = Uri.parse(url);

                                  // Try different launch modes for better compatibility
                                  bool launched = false;

                                  // First try: Force external application
                                  try {
                                    launched = await launchUrl(
                                      uri,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  } catch (e) {
                                    print('External app launch failed: $e');
                                  }

                                  // Second try: In-app web view
                                  if (!launched) {
                                    try {
                                      launched = await launchUrl(
                                        uri,
                                        mode: LaunchMode.inAppWebView,
                                      );
                                    } catch (e) {
                                      print(
                                        'In-app web view launch failed: $e',
                                      );
                                    }
                                  }

                                  // Third try: Platform default
                                  if (!launched) {
                                    try {
                                      launched = await launchUrl(uri);
                                    } catch (e) {
                                      print(
                                        'Platform default launch failed: $e',
                                      );
                                    }
                                  }

                                  if (launched) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Opening in browser...',
                                          ),
                                          duration: Duration(seconds: 1),
                                        ),
                                      );
                                    }
                                  } else {
                                    // Copy URL as fallback
                                    await Clipboard.setData(
                                      ClipboardData(text: url),
                                    );
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Could not open browser. URL copied to clipboard instead!',
                                          ),
                                          duration: Duration(seconds: 3),
                                        ),
                                      );
                                    }
                                  }
                                } catch (e) {
                                  // Fallback: copy to clipboard
                                  await Clipboard.setData(
                                    ClipboardData(text: url),
                                  );
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Browser launch failed. URL copied to clipboard!',
                                        ),
                                        duration: Duration(seconds: 3),
                                      ),
                                    );
                                  }
                                }
                              },
                              tooltip: 'Open in browser',
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            onPressed: _server == null ? _startServer : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Start Server'),
                          ),
                          ElevatedButton(
                            onPressed: _server != null ? _stopServer : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Stop Server'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // File Management Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'HTML Files (${_selectedFiles.length})',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _pickHtmlFiles,
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text(
                                    'Add',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    minimumSize: const Size(0, 36),
                                  ),
                                ),
                                if (_selectedFiles.isNotEmpty)
                                  ElevatedButton.icon(
                                    onPressed: _clearAllFiles,
                                    icon: const Icon(Icons.clear_all, size: 16),
                                    label: const Text(
                                      'Clear',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      minimumSize: const Size(0, 36),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_selectedFiles.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.file_open,
                                  size: 48,
                                  color: Colors.grey,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'No HTML files selected',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Tap "Add Files" to select HTML files from your device',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _selectedFiles.length,
                          itemBuilder: (context, index) {
                            final file = _selectedFiles[index];
                            final fileName = path.basename(file.path);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(
                                  Icons.html,
                                  color: Colors.orange,
                                ),
                                title: Text(fileName),
                                subtitle: Text(
                                  file.path,
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_server != null)
                                      IconButton(
                                        icon: const Icon(Icons.open_in_browser),
                                        onPressed: () async {
                                          final url =
                                              _serverAddress.split(' on ')[1];
                                          // URL encode the filename to handle spaces and special characters
                                          final encodedFileName =
                                              Uri.encodeComponent(fileName);
                                          final fileUrl =
                                              '$url/$encodedFileName';
                                          try {
                                            final uri = Uri.parse(fileUrl);
                                            await launchUrl(uri);
                                          } catch (e) {
                                            await Clipboard.setData(
                                              ClipboardData(text: fileUrl),
                                            );
                                            if (mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'URL copied to clipboard!',
                                                  ),
                                                  duration: Duration(
                                                    seconds: 2,
                                                  ),
                                                ),
                                              );
                                            }
                                          }
                                        },
                                        tooltip: 'Open file in browser',
                                      ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                      ),
                                      onPressed: () => _removeFile(index),
                                      tooltip: 'Remove file',
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
