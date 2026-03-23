import 'dart:io';
import 'package:path/path.dart' as path;


class Config {
  Config._(); // 私有构造函数，防止实例化

  static const int udpPort = 8888;
  static const int tcpPort = 9999;

  static const String udpDiscoveryPrefix = "UDP_DISCOVERY";
  static const String udpProbePrefix = "UDP_PROBE";
  static const String tcpMessagePrefix = "TCP_MESSAGE";

  static const int heartbeatInterval = 3000;
  static const int peerTimeout = 10000;

  static String receivedFilesDir = path.join(Directory.current.path, "received_files");

  static String getReceivedFilePath(String fileName) {
    String dir = path.join(Directory.current.path, "received_files");
    Directory(dir).createSync(recursive: true);
    return path.join(dir, fileName);
  }
}