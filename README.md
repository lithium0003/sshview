# sshview

app link
https://apps.apple.com/us/app/id1620680161


<img src="https://github.com/lithium0003/sshview/blob/main/sshview/Assets.xcassets/AppIcon.appiconset/1024.png" width="160px">

This app is SSH viewer. SSH terminal and local port forward is available. SSH proxy jump connection is available with port forwarding.
App has a internal web viewer for local port forwarding.
SSH connection is open and running commands for example tensorboard, jupyter notebook, and port forward on the server to the local device, open the forwarding port with a browser.
You can see the tensorbord or jupyter notebook from remote server on your iPhone and iPad via SSH connection.

## License

This app depends on OpenSSL library https://github.com/openssl/openssl and libssh library https://www.libssh.org/

libssh is LGPL 2.1, openssl is Apache License 2.0,
This app build with static link, so the app is LGPL 2.1

## Screenshots

<p float="left">
<img src="https://lithium03.info/ios/sshview/screen1.png" width="320px">
<img src="https://lithium03.info/ios/sshview/screen2.png" width="320px">
<img src="https://lithium03.info/ios/sshview/screen3.png" width="320px">
<img src="https://lithium03.info/ios/sshview/screen4.png" width="320px">
<img src="https://lithium03.info/ios/sshview/screen5.png" width="320px">
<img src="https://lithium03.info/ios/sshview/screen6.png" width="320px">
<img src="https://lithium03.info/ios/sshview/screen7.png" width="320px">
</p>

## How to use (iPhone and iPad)

### Make user

First, you add user identity entry.
Open the app top and tap "User ID", add new user by right top + button.

<img src="https://lithium03.info/ios/sshview/add_user1.png" width="320px">

This new user page, you need to fill the Tag, Username, and private key (and passphrase if you need).
You can copy and paste the private key on the textbox, or load from a file. And also, generate new key pair. 

<img src="https://lithium03.info/ios/sshview/add_user2.png" width="320px">

New keypair generateion window, you can choose key type and if you want passphrase protection, enter the passphrase, and tap generate.
After generateion, public key can copy or export to file. 

### Add server

Next, you add server. Open the app top and tap "Servers", add new server by right top + button. 

<img src="https://lithium03.info/ios/sshview/add_server1.png" width="320px">

This new server page, you need to fill the Tag, Hostname, Port, and select user ID.
Default connection type is normal terminal. 

### Connect server

After addition of server, you can connect remmote server from Server list page. 

<img src="https://lithium03.info/ios/sshview/screen2.png" width="320px">

Tap the entry, SSH connection start. 

### Edit server infomation

In server list page, swipe to right or long tap, you can edit server infomation.
You want to remove the server, swipe to left. 

### Proxy jump

You need to connect with proxy jump, first add the proxy server, and then add the main server.
In server infomation, Proxy jump server selection menu can specify the proxy server connection. 
Set the proxy, SSH connection to the main server is automatically on the tunnel to a proxy server. 

### Remote command

Server connection type is set "Command", no pty is open, just run the commands.
You can see the stdin and stdout on the display.

### WebBrowser on local port forward

Server connection type is set "WebBrowser", you can see the web page on the server via local port forwarding.
You can choose fixed port number or, dynamic port/address selection.
Dynamic selection is grep the commands output and find token of port/address.
Grep string is preset for tensorboard and jupyter notebook.
Alredy running on the server and open the port, you can keep remote command field is empty.
Some command is need to run on connection, you enter the commands. 


## build

First, build library.

``` bash
cd library
./build.sh
```

If build ssuccessfully, library/install folder has include and lib.

Then, compile with XCode.


