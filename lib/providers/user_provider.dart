import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// 集中管理當前登入用戶的即時資料（暱稱、頭像）。
/// 任何頁面 context.watch<UserProvider>() 即可取得最新值。
class UserProvider extends ChangeNotifier {
  StreamSubscription<DocumentSnapshot>? _firestoreSub;

  String? _uid;
  String  _nickname = '';
  String  _photoURL = '';

  String? get uid       => _uid;
  String  get nickname  => _nickname;
  String  get photoURL  => _photoURL;

  /// 登入後呼叫，開始監聽 users/{uid}。
  void init(User user) {
    if (_uid == user.uid) return; // 同一用戶不重複初始化
    _uid      = user.uid;
    _nickname = user.displayName ?? '';
    _photoURL = user.photoURL    ?? '';
    notifyListeners();

    _firestoreSub?.cancel();
    _firestoreSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((doc) {
      final data = doc.data() ?? {};
      final name  = (data['nickname'] as String? ?? '').trim();
      final photo = (data['photoURL']  as String? ?? '').trim();
      _nickname = name.isNotEmpty  ? name  : (user.displayName ?? '');
      _photoURL = photo.isNotEmpty ? photo : (user.photoURL    ?? '');
      notifyListeners();
    });
  }

  /// 登出後呼叫，清空資料。
  void clear() {
    _firestoreSub?.cancel();
    _firestoreSub = null;
    _uid      = null;
    _nickname = '';
    _photoURL = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _firestoreSub?.cancel();
    super.dispose();
  }
}
