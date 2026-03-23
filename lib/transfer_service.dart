import 'dart:convert';
import 'dart:io';
import 'package:logger/logger.dart';
import 'config.dart';
import 'dart:async';

class TransferTask{
  Socket client;
  Map<String, dynamic> message;
  final Stream<List<int>> fileDataStream; // 用于传输文件数据的流
  TransferTask({required this.client, required this.message, required this.fileDataStream});
}
class TransferService {
  
  ServerSocket? _serverSocket;
  final _controller = StreamController<TransferTask>.broadcast();
  Stream<TransferTask> get onMessageReceived => _controller.stream;

  Future<void> start() async{
    _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, Config.tcpPort);

    _serverSocket!.listen((Socket client) {
      Logger().i("New connection from ${client.remoteAddress.address}:${client.remotePort}");

      var fileDataStreamController = StreamController<List<int>>(); // 这里暂时用一个空流占位，实际使用时需要根据协议来确定何时开始传输文件数据      
      bool handledRequest = false; // 标记是否已经处理过请求
      int totalBytesReceived = 0; // 用于统计接收的字节数
      int expectedFileSize = 0; // 预期的文件大小，初始为0，实际使用时需要根据协议来确定何时设置这个值

      client.listen((data) {
        if(!handledRequest){
          try{
              Map<String, dynamic> message = jsonDecode(utf8.decode(data));
              Logger().i("Received message: $message");
              handledRequest = true; // 标记已经处理过请求，后续数据将被视为文件数据
              if(message["type"] == "request_to_send"){
                expectedFileSize = message["size"] ?? 0; // 从消息中获取预期的文件大小
                Future.delayed(const Duration(milliseconds: 500), (){
                  _controller.add(TransferTask(client: client, message: message, fileDataStream: fileDataStreamController.stream));
                });
              }
              else{
                // todo: 处理其他请求
              }
          }
          catch(e){
            Logger().e("Failed to parse message: $e");
            client.close();
          }
        }
        else{
          if(!fileDataStreamController.isClosed){
            fileDataStreamController.add(data); // 将后续数据视为文件数据
            totalBytesReceived += data.length;
            }
          }
      },
      onError: (error) {
        Logger().e("Error on connection with ${client.remoteAddress.address}:${client.remotePort} - $error");
        client.close();
      },
      onDone: () {
        Logger().i("Connection closed by ${client.remoteAddress.address}:${client.remotePort}");
        if(!fileDataStreamController.isClosed){
          fileDataStreamController.close(); // 连接关闭时确保文件数据流也被关闭
        }
      }
      );
    });
  }

  Future<Socket> connectToPeer(String ip) async {
    Socket socket = await Socket.connect(ip, Config.tcpPort);
    Logger().i("Connected to peer at $ip");
    return socket;
  }

  void acceptTransferRequest(TransferTask task){
    // 这里可以添加一些逻辑来处理接受传输请求的情况，比如准备接收文件等
    Logger().i("Accepted transfer request: ${task.message}");
    Socket client = task.client;
    Map<String, dynamic> response = {
      "type": "accept_request",
      "message": "请求已被接受，准备发送文件"
    };
    client.add(utf8.encode(jsonEncode(response)));
  }

  void rejectTransferRequest(TransferTask task){
    // 这里可以添加一些逻辑来处理拒绝传输请求的情况，比如发送拒绝消息等
    Logger().i("Rejected transfer request: ${task.message}");
    Socket client = task.client;
    Map<String, dynamic> response = {
      "type": "reject_request",
      "message": "请求已被拒绝"
    };
    client.add(utf8.encode(jsonEncode(response)));
    client.close();
  }


  void dispose(){
    _serverSocket?.close();
    _controller.close();
  }
}