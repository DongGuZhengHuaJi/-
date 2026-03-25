import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TransferHistory {
  final String name;
  final double size;
  final String time;
  final String path;
  final bool isSender;
  final bool isSuccess;

  TransferHistory({
    required this.name,
    required this.size,
    required this.time,
    this.path = "",
    required this.isSender,
    required this.isSuccess,
  });

  // 转为 Map 以便转成 JSON 字符串
  Map<String, dynamic> toJson() => {
    'name': name,
    'size': size,
    'time': time,
    'isSender': isSender,
    'isSuccess': isSuccess,
    'path': path,
  };

  // 从 JSON 字符串转回对象
  factory TransferHistory.fromJson(Map<String, dynamic> json) => TransferHistory(
    name: json['name'],
    size: json['size'],
    time: json['time'],
    isSender: json['isSender'],
    isSuccess: json['isSuccess'],
    path: json['path'] ?? "",
  );
}

class TransferHistoryManager {
  static const String _key = 'transfer_history';

  static final ValueNotifier<List<TransferHistory>> historyNotifier = ValueNotifier<List<TransferHistory>>([]);

  static Future<void> start() async {
    List<TransferHistory> history = await getHistory();
    historyNotifier.value = history;
  }

  static Future<List<TransferHistory>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonString = prefs.getString(_key);
    if (jsonString == null) return [];
    List<dynamic> jsonList = jsonDecode(jsonString);
    return jsonList.map((json) => TransferHistory.fromJson(json)).toList();
  }

  static Future<void> addHistory(TransferHistory history) async {
    final currentList = historyNotifier.value;
    currentList.insert(0, history); // 插入到最前面
    String jsonString = jsonEncode(currentList.map((h) => h.toJson()).toList());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonString);
    historyNotifier.value = List.from(currentList); // 触发更新
  }


  static Future<void> deleteHistorys(Set<int> indices) async {
    final currentList = historyNotifier.value;
    List<TransferHistory> newList = [];
    for (int i = 0; i < currentList.length; i++) {
      if (!indices.contains(i)) {
        newList.add(currentList[i]);
      }
    }
    String jsonString = jsonEncode(newList.map((h) => h.toJson()).toList());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonString);
    historyNotifier.value = newList; // 直接赋值新列表
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    historyNotifier.value = [];
  }
}
