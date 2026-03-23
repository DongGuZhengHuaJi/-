import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'user_profile.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'config.dart';
import 'dart:async';

class PeerInfo {
  final String uuid;
  final String name;
  final String ip;
  DateTime lastSeen;

  PeerInfo({required this.uuid, required this.name, required this.ip})
      : lastSeen = DateTime.now();
}

class UserInfo {
  final String userUuid;
  final String userName;
  final String? ip;
  UserInfo({required this.userName, required this.userUuid, this.ip});
}

class DiscoverService {
  RawDatagramSocket? _socket;
  UserInfo? myInfo;
  Map<String, PeerInfo> discoveredPeers = {};
  ValueNotifier<Map<String, PeerInfo>> peersNotifier = ValueNotifier({});
  Timer? _findPeersTimer;
  Timer? _cleanupPeersTimer;
  

  Future<void> start() async{
    var userInfo = await UserProfile.loadUserProfile();
    String? myIp = await getMyIp();
    if(myIp == "获取 IP 失败" || myIp == "未连接 Wi-Fi"){
      Logger().e("Cannot start DiscoverService without a valid IP address.");
      return;
    }

    myInfo = UserInfo(
      userName: userInfo["user_name"] ?? "匿名用户",
      userUuid: userInfo["user_uuid"] ?? "未知 UUID",
      ip: myIp,
    );
    Logger().i("User Info loaded in start(): ${myInfo!.userName}, ${myInfo!.userUuid}"); // 这里可以看到加载的用户信息

    Logger().i("Device IP address: ${myInfo!.ip}");
    
    await _setupSocket();

  }

  Future<String?> getMyIp() async {
    try {
      String? ip = await NetworkInfo().getWifiIP();
      return ip ?? "未连接 Wi-Fi";
    } catch (e) {
      Logger().e("Failed to get IP address: $e");
      return "获取 IP 失败";
    }
  }

  Future<void> _setupSocket() async {
    try{
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, Config.udpPort);
      _socket!.broadcastEnabled = true;

      _socket!.listen((event) {
        if (event == RawSocketEvent.read) {
          Datagram? datagram = _socket!.receive();
          if (datagram != null) {
            _handleIncomingMessage(datagram);
          }
        }
      });

      String discoveryMessage = "${Config.udpDiscoveryPrefix}:${myInfo!.userUuid}:${myInfo!.userName}";
      _sendBroadcast(discoveryMessage);

      _findPeersTimer = Timer.periodic(Duration(seconds: 5), (timer) {
        _sendBroadcast(discoveryMessage);
        _sendAllPeers(discoveryMessage);
      });

      _cleanupPeersTimer = Timer.periodic(Duration(seconds: 10), (timer) {
        DateTime now = DateTime.now();
        discoveredPeers.removeWhere((uuid, peer) => now.difference(peer.lastSeen) > Duration(seconds: 15));
        if(peersNotifier.value.length != discoveredPeers.length){
          peersNotifier.value = Map.from(discoveredPeers);
        }
      });
    }
    catch(e){
      Logger().e("Failed to bind UDP socket: $e");
    }
  }

  void _sendBroadcast(String message) {
    if(_socket == null) {
      Logger().e("UDP socket is not initialized. Cannot send message.");
      return;
    }
    else if(myInfo!.ip == null) {
      Logger().e("IP address is not available. Cannot send message.");
      return;
    }

    _socket!.send(utf8.encode(message), InternetAddress("255.255.255.255"), Config.udpPort);
  }

  void _sendAllPeers(String message) {
    if(_socket == null) {
      Logger().e("UDP socket is not initialized. Cannot send message.");
      return;
    }
    if(myInfo!.ip == null) {
      Logger().e("IP address is not available. Cannot send message.");
      return;
    }

    discoveredPeers.forEach((uuid, peer) {
      _socket!.send(utf8.encode(message), InternetAddress(peer.ip), Config.udpPort);
    });
  }

  void _handleIncomingMessage(Datagram datagram) {
    // if (datagram.address.address == myInfo!.ip) {
    //   return;
    // }
    String senderIp = datagram.address.address;
    String message = utf8.decode(datagram.data);
    Logger().i("Received UDP message: $message from ${datagram.address.address}:${datagram.port}");

    if (message.startsWith(Config.udpDiscoveryPrefix)) {
      List<String> parts = message.split(":");
      if (parts.length >= 3) {
        String senderUuid = parts[1];
        String senderName = parts[2];
        if(senderUuid == myInfo!.userUuid){
          return;
        }
        
        if(discoveredPeers.containsKey(senderUuid)){
          discoveredPeers[senderUuid]!.lastSeen = DateTime.now();
        }
        else{
          Logger().i("Discovered peer: $senderName (UUID: $senderUuid) at IP: ${datagram.address.address}");
          discoveredPeers[senderUuid] = PeerInfo(
            uuid: senderUuid,
            name: senderName,
            ip: senderIp,
          );
          peersNotifier.value = Map.from(discoveredPeers);
        }
      }
    }
    else if(message.startsWith(Config.udpProbePrefix)){
      List<String> parts = message.split(":");
      if (parts.length >= 3) {
        String senderUuid = parts[1];
        String senderName = parts[2];
        if(senderUuid == myInfo!.userUuid){
          return;
        }
        Logger().i("Received probe response from $senderName (UUID: $senderUuid) at IP: ${datagram.address.address}");
        discoveredPeers[senderUuid] = PeerInfo(
          uuid: senderUuid,
          name: senderName,
          ip: senderIp,
        );
        peersNotifier.value = Map.from(discoveredPeers);
      }
    }
  }

  void probePeerByIp(String ip) {
    String probeMessage = "${Config.udpProbePrefix}:${myInfo!.userUuid}:${myInfo!.userName}";
    if(_socket == null) {
      Logger().e("UDP socket is not initialized. Cannot send probe message.");
      return;
    }
    _socket!.send(utf8.encode(probeMessage), InternetAddress(ip), Config.udpPort);
    Logger().i("Sent probe message to $ip");
  }

  void dispose() {
    _socket?.close();
    _findPeersTimer?.cancel();
    _cleanupPeersTimer?.cancel();
  }

}
