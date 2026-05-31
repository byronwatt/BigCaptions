# BigCaptions

BigCaptions is an iOS app designed for deaf and low-vision users, providing real-time, high-visibility live captioning.

## Features
- **Voice-to-Text:** Real-time transcription using Apple's Speech Recognition.
- **Enhanced Visibility:** Large, bold fonts with high contrast (white text on black).
- **Customizable Font Size:** Adjust the font size from 20 to 100 in the settings.
- **Smart Scrolling:** Auto-scrolls to the latest words, but pauses if you scroll back to read earlier text.
- **Jump to Latest:** Quickly return to the live transcription with a single tap.

## How to Build and Install
1. **Push to GitHub:** Upload this entire `BigCaptions` folder to your GitHub repository.
2. **GitHub Actions:** The included workflow (`.github/workflows/build-artifact.yml`) will automatically trigger a build when you push to the `main` branch.
3. **Download Artifact:** Once the workflow finishes, go to the "Actions" tab in your GitHub repo, select the latest run, and download the `BigCaptions-App` artifact.
4. **Install via USB:**
   - Unzip the downloaded file to get `BigCaptions.ipa`.
   - Connect your iPhone or iPad to your Mac.
   - Use a tool like **Apple Configurator 2** or **Xcode** (Devices and Simulators window) to drag and drop the `.ipa` file onto your device.
   - *Note: Since this is an unsigned build, you may need to trust the developer in your device's Settings > General > VPN & Device Management.*

## Permissions
The app requires the following permissions to function:
- **Microphone:** To capture audio for transcription.
- **Speech Recognition:** To process the audio into text.
