# Installation Guide for BigCaptions

Follow these steps to download and install the BigCaptions app on your iPhone or iPad using your Mac.

## Prerequisites
- A Mac with **Apple Configurator** (free on the Mac App Store) or **Xcode** installed.
- A USB cable to connect your device to your Mac.

## Step 1: Download the App from GitHub
1. Go to the [Actions tab](https://github.com/byronwatt/BigCaptions/actions) of your repository.
2. Click on the most recent successful (green) workflow run.
3. Scroll down to the **Artifacts** section at the bottom.
4. Click on **BigCaptions-App** to download the zip file.
5. On your Mac, double-click the downloaded zip file to extract it. You will see a file named `BigCaptions.ipa`.

## Step 2: Install via USB (Using Apple Configurator)
1. Open **Apple Configurator** on your Mac.
2. Connect your iPhone or iPad to your Mac via USB.
3. Your device should appear in the Apple Configurator window.
4. Drag and drop the `BigCaptions.ipa` file directly onto the image of your device.
5. Wait for the installation to complete.

*Note: If you prefer using Xcode, open the "Devices and Simulators" window (Cmd+Shift+2) and drag the `.ipa` into the "Installed Apps" section.*

## Step 3: Trust the App on your Device
Since this is a custom build, iOS will initially block it for security.
1. On your iPhone or iPad, open **Settings**.
2. Go to **General** > **VPN & Device Management** (or **Profiles & Device Management**).
3. Under "Developer App," tap on your Apple ID/Profile.
4. Tap **Trust [Your Name/Email]**.
5. Tap **Trust** again to confirm.

## Step 4: Launch BigCaptions
You can now find the **BigCaptions** icon on your home screen. Open it, grant Microphone and Speech Recognition permissions when prompted, and tap the record button to start live captioning!
