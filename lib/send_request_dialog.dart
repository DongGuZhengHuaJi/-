import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'transfer_service.dart';
import 'package:logger/logger.dart';

class SendRequestDialog extends StatefulWidget {
  final String targetIp;
  final String myName;
  final String path;
  final String name;
  final double size;
  final TransferService service;
  final Function(Socket) onAccept;

  const SendRequestDialog({super.key, required this.targetIp, required this.myName, required this.path, required this.name, required this.size, required this.service, required this.onAccept});
  @override
  State<SendRequestDialog> createState() => _SendRequestDialogState();
}

class _SendRequestDialogState extends State<SendRequestDialog> {
  String _status = "正在发送请求...";
  bool _isError = false;
  Socket? _socket;

  @override
  void initState() {
    super.initState();
    _startWork();
  }

  Future<void> _startWork() async {
    try{
      _socket = await widget.service.connectToPeer(widget.targetIp);
      if(!mounted) return;

      setState(() {
        _status = "请求已发送，等待对方响应...";
      });

      _socket!.add(utf8.encode(jsonEncode({
        "type": "request_to_send",
        "from": widget.myName,
        "message": "请求发送文件",
        "path": widget.path,
        "name": widget.name,
        "size": widget.size
      }))); 

      _socket!.listen((data){
          Map<String, dynamic> response = jsonDecode(utf8.decode(data));
          if(response["type"] == "accept_request"){
            setState(() {
              _status = "请求被接受，准备发送文件...";
            });
            Future.delayed(const Duration(milliseconds: 500), (){
              if(mounted){
                Navigator.of(context).pop();
                widget.onAccept(_socket!);
              }
            });
          }
          else if(response["type"] == "reject_request"){
              _handleFailure("请求被拒绝");
          }
          else{
            Logger().i("Received unknown response: $response");
          }
        }
      );
    }
    catch(e){
      _handleFailure("连接失败: $e");
    }
  }

  void _handleFailure(String message){
    setState(() {
      _status = message;
      _isError = true;
    });
    _socket?.destroy();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("文件传输"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if(!_isError) const Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: CircularProgressIndicator(),
          ),
          if(_isError) const Icon(Icons.error, color: Colors.red, size: 48),
          Text("传输文件: ${widget.name} (${(widget.size / 1024).toStringAsFixed(2)} KB)"),
          Text(_status),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(_isError ? "关闭" : "取消"),
        ),
      ],
    );
  }
}