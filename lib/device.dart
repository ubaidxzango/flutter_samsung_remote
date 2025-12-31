import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';

import 'key_codes.dart';

final int kConnectionTimeout = 60;
final kKeyDelay = 200;
final kWakeOnLanDelay = 5000;
final kUpnpTimeout = 1000;

// import wol from 'wake_on_lan'
// import WebSocket from 'ws'
// import request from 'request-promise'
// import SSDP from 'node-ssdp'

// import { getLogger } from 'appium-logger'
// import { KEY_CODES } from './constants'

// const log = getLogger('SamsungRemote')

// const CONNECTION_TIMEOUT = 60000
// const KEY_DELAY = 200
// const WAKE_ON_LAN_DELAY = 5000
// const UPNP_TIMEOUT = 1000

class SamsungSmartTV {
  final List<Map<String, dynamic>> services;
  final String? host;
  final String? mac;
  final String? api;
  final String? wsapi;
  bool isConnected = false;
  String? token;
  dynamic info;
  late IOWebSocketChannel ws;
  late Timer timer;

  SamsungSmartTV({
    this.host,
    this.mac,
  })  : api = "http://$host:8001/api/v2/",
        wsapi = "wss://$host:8002/api/v2/",
        services = [];

  /**
     * add UPNP service
     * @param [Object] service  UPNP service description
     */
  addService(service) {
    this.services.add(service);
  }

  connect({appName = 'DartSamsungSmartTVDriver'}) async {
    var completer = new Completer();

    if (this.isConnected) {
      return;
    }

    // // make sure to turn on TV in case it is turned off
    // if (mac != null) {
    //   await this.wol(this.mac);
    // }

    // get device info
    info = await getDeviceInfo();

    // establish socket connection
    final appNameBase64 = base64.encode(utf8.encode(appName));
    String channel =
        "${wsapi}channels/samsung.remote.control?name=$appNameBase64";
    channel += '&token=$token';

    // log.info(`Connect to ${channel}`)
    // ws = IOWebSocketChannel.connect(channel);
    ws = IOWebSocketChannel.connect(
      channel,
      // badCertificateCallback: (X509Certificate cert, String host, int port) =>
      //     true
    );

    ws.stream.listen((message) {
      // timer?.cancel();

      Map<String, dynamic> data;
      try {
        data = json.decode(message);
      } catch (e) {
        throw ('Could not parse TV response $message');
      }

      if (data["data"] != null && data["data"]["token"] != null) {
        token = data["data"]["token"];
      }

      if (data["event"] != 'ms.channel.connect') {
        print('TV responded with $data');

        // throw ('Unable to connect to TV');
      }

      print('Connection successfully established');
      isConnected = true;
      completer.complete();

      // timer = Timer(Duration(seconds: kConnectionTimeout), () {
      //   throw ('Unable to connect to TV: timeout');
      // });

      // ws.sink.add("received!");
    });

    return completer.future;
  }

  // request TV info like udid or model name

  Future<http.Response> getDeviceInfo() async {
    print("Get device info from $api");
    return http.get(Uri.parse(this.api ?? ''));
  }

  // disconnect from device

  disconnect() {
    // ws.sink.close(status.goingAway);
    ws.sink.close();
  }

  sendKey(KEY_CODES key) async {
    if (!isConnected) {
      throw ('Not connected to device. Call `tv.connect()` first!');
    }

    print("Send key command  ${key.toString().split('.').last}");
    final data = json.encode({
      "method": 'ms.remote.control',
      "params": {
        "Cmd": 'Click',
        "DataOfCmd": key.toString().split('.').last,
        "Option": false,
        "TypeOfRemote": 'SendRemoteKey',
      }
    });

    ws.sink.add(data);

    // add a delay so TV has time to execute
    Timer(Duration(seconds: kConnectionTimeout), () {
      throw ('Unable to connect to TV: timeout');
    });

    return Future.delayed(Duration(milliseconds: kKeyDelay));
  }

  // Discover Samsung TVs using SSDP (null-safe, no upnp dependency)
//   static Future<SamsungSmartTV> discover(
//       {Duration timeout = const Duration(seconds: 5)}) async {
//     final completer = Completer<SamsungSmartTV>();
//     final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
//     socket.broadcastEnabled = true;

//     const ssdpAddress = '239.255.255.250';
//     const ssdpPort = 1900;

//     final searchRequest = '''
// M-SEARCH * HTTP/1.1
// HOST: $ssdpAddress:$ssdpPort
// MAN: "ssdp:discover"
// MX: 2
// ST: ssdp:all

// ''';

//     socket.send(
//       utf8.encode(searchRequest),
//       InternetAddress(ssdpAddress),
//       ssdpPort,
//     );

//     final timer = Timer(timeout, () {
//       if (!completer.isCompleted) {
//         completer.completeError(
//           'No Samsung TVs found. Make sure the TV and phone are on the same network.',
//         );
//       }
//       socket.close();
//     });

//     socket.listen((event) {
//       if (event == RawSocketEvent.read) {
//         final datagram = socket.receive();
//         if (datagram == null) return;

//         final response = utf8.decode(datagram.data, allowMalformed: true);

//         // Basic Samsung TV identification
//         if (response.toLowerCase().contains('samsung')) {
//           final locationLine = response.split('\n').firstWhere(
//                 (l) => l.toLowerCase().startsWith('location:'),
//                 orElse: () => '',
//               );

//           if (locationLine.isNotEmpty) {
//             final uri = Uri.tryParse(locationLine.split(':')[1].trim());
//             if (uri?.host != null && !completer.isCompleted) {
//               timer.cancel();
//               socket.close();
//               completer.complete(SamsungSmartTV(host: uri!.host));
//             }
//           }
//         }
//       }
//     });

//     return completer.future;
//   }

// Discover TVs using SSDP (null-safe, no upnp dependency)
  static Future<void> discover(
      {Duration timeout = const Duration(seconds: 5)}) async {
    print('[SSDP] Starting network discovery for TVs...');
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;

    const ssdpAddress = '239.255.255.250';
    const ssdpPort = 1900;

    final searchRequest = '''
M-SEARCH * HTTP/1.1
HOST: $ssdpAddress:$ssdpPort
MAN: "ssdp:discover"
MX: 2
ST: ssdp:all

''';

    print('[SSDP] Sending M-SEARCH broadcast');
    socket.send(
      utf8.encode(searchRequest),
      InternetAddress(ssdpAddress),
      ssdpPort,
    );

    final timer = Timer(timeout, () {
      print('[SSDP] Discovery completed or timed out');
      socket.close();
    });

    socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram == null) return;

        final response = utf8.decode(datagram.data, allowMalformed: true);

        // Log all SSDP responses for debugging
        print('[SSDP] Response received:\n$response');

        // Basic filtering for TVs (Samsung, Android TV, Google TV, etc.)
        final isTV = response.toLowerCase().contains('samsung') ||
            response.toLowerCase().contains('android') ||
            response.toLowerCase().contains('roku') ||
            response.toLowerCase().contains('google');

        if (isTV) {
          print('[SSDP] TV detected on network');
        }
      }
    });
  }
}
