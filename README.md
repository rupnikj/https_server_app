# Local HTML File Server (Flutter)

A Flutter application that allows you to select local HTML files from your device and serve them over a local HTTP or HTTPS server. The app provides a simple UI to manage the server and the files being served.

## Features

*   **Start/Stop Server**: Easily start and stop the local web server.
*   **File Selection**: Pick multiple HTML files (`.html`, `.htm`) from your device's storage.
*   **Serves HTML Files**: Makes the selected HTML files accessible via a local URL.
*   **Dynamic Index Page**: Automatically generates an index page listing all served files, with links to each.
*   **Server Information**: Displays the current server address (IP and port).
*   **Quick Actions**:
    *   Copy the server URL to the clipboard.
    *   Open the server URL (or individual served files) directly in a browser.
*   **File Management**:
    *   Add new HTML files to the serving list.
    *   Remove specific files from the list.
    *   Clear all selected files.
*   **HTTPS Capable**: Includes setup for HTTPS using `server.crt` and `server.key` from the `assets` folder. (Currently defaults to HTTP for development convenience).

## How It Works

The application is built with Flutter and utilizes several Dart packages:

*   `shelf`: For creating the underlying web server.
*   `file_picker`: To allow users to select HTML files.
*   `url_launcher`: To open URLs in the default browser.

When files are selected, their content is pre-loaded into memory for faster serving. The server listens for incoming requests and serves either the index page or the content of a requested HTML file.

## Getting Started

### Prerequisites

*   Flutter SDK installed on your system.
*   A compatible device or emulator.

### Running the App

1.  **Clone the repository:**
    ```bash
    git clone <repository-url>
    cd https_server_app
    ```
2.  **Get dependencies:**
    ```bash
    flutter pub get
    ```
3.  **Run the app:**
    ```bash
    flutter run
    ```

## SSL Certificates & Server Configuration

The application is set up to support HTTPS. It expects `server.crt` (certificate chain) and `server.key` (private key) files to be present in the `assets/` directory.

*   **Sample certificates are included in the `assets` folder.** For actual secure local use or if you encounter trust issues, you should generate your own self-signed certificates or use ones from a local CA.
*   **Current Default**: In `lib/main.dart`, the `useHttps` variable is currently set to `false`. This makes the server run as **HTTP on `127.0.0.1:8080`** (or the first available non-loopback IPv4 address on port 8080).
*   **To enable HTTPS**:
    1.  Change the `useHttps` variable in `lib/main.dart` to `true`.
    2.  Ensure your `assets/server.crt` and `assets/server.key` are valid.
    3.  The server will then attempt to run on **HTTPS, typically on port 8443**.

## Project Structure

*   `lib/main.dart`: Contains the main application logic, UI, and server implementation.
*   `pubspec.yaml`: Defines project dependencies, assets, and metadata.
*   `assets/`: Contains static assets like SSL certificates.
*   Platform-specific directories (`android/`, `ios/`, `linux/`, `macos/`, `web/`, `windows/`): Standard Flutter folders for building the app on respective platforms.


