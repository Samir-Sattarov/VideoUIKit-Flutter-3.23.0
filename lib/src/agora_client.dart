import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:agora_uikit/controllers/rtc_buttons.dart';
import 'package:agora_uikit/controllers/session_controller.dart';
import 'package:agora_uikit/models/agora_channel_data.dart';
import 'package:agora_uikit/models/agora_connection_data.dart';
import 'package:agora_uikit/models/agora_rtc_event_handlers.dart';
import 'package:agora_uikit/models/agora_rtm_channel_event_handler.dart';
import 'package:agora_uikit/models/agora_rtm_client_event_handler.dart';
import 'package:agora_uikit/models/cloud_storage_data.dart';
import 'package:agora_uikit/src/enums.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

/// [AgoraClient] is the main class in this VideoUIKit. It is used to initialize our [RtcEngine], add the list of user permissions, define the channel properties and use extend the [RtcEngineEventHandler] class.
class AgoraClient {
  /// [AgoraConnectionData] is a class used to store all the connection details to authenticate your account with the Agora SDK.
  final AgoraConnectionData agoraConnectionData;

  /// [CloudStorageData] is a class used to store all the connection details to connect your app with the Agora Cloud Recording service.
  final CloudStorageData? cloudStorageData;

  /// [enabledPermission] is a list of permissions that the user has to grant to the app. By default the UIKit asks for the camera and microphone permissions for every broadcaster that joins the channel.
  final List<Permission>? enabledPermission;

  /// [AgoraChannelData] is a class that contains all the Agora channel properties.
  final AgoraChannelData? agoraChannelData;

  /// [AgoraRtcEventHandlers] is a class that contains all the Agora RTC event handlers. Use it to add your own functions or methods.
  final AgoraRtcEventHandlers? agoraEventHandlers;

  /// [AgoraRtmClientEventHandlers] is a class that contains all the Agora RTM Client event handlers. Use it to add your own functions or methods.
  final AgoraRtmClientEventHandler? agoraRtmClientEventHandler;

  /// [AgoraRtmChannelEventHandlers] is a class that contains all the Agora RTM channel event handlers. Use it to add your own functions or methods.
  final AgoraRtmChannelEventHandler? agoraRtmChannelEventHandler;

  bool _initialized = false;

  AgoraClient({
    required this.agoraConnectionData,
    this.cloudStorageData,
    this.enabledPermission,
    this.agoraChannelData,
    this.agoraEventHandlers,
    this.agoraRtmClientEventHandler,
    this.agoraRtmChannelEventHandler,
  }) : _initialized = false;

  /// Useful to check if [AgoraClient] is ready for further usage
  bool get isInitialized => _initialized;

  //this cannot be used by the user or cloud recording won't work
  final String cloudRecordingId = "101";
  String _cloudRecordingCredential = "";
  String? _cloudRecordingResourceId;
  String get cloudRecordingCredential => _cloudRecordingCredential;
  String? get cloudRecordingResourceId => _cloudRecordingResourceId;
  resetResourceId() => _cloudRecordingResourceId = null;

  String? _sid;
  set setSid(String? sid) => _sid = sid;
  String? get sid => _sid;

  static const MethodChannel _channel = MethodChannel('agora_uikit');

  static Future<String> platformVersion() async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  List<int> get users {
    final List<int> version =
        _sessionController.value.users.map((e) => e.uid).toList();
    return version;
  }

  // This is our "state" object that the UI Kit works with
  final SessionController _sessionController = SessionController();
  SessionController get sessionController {
    return _sessionController;
  }

  RtcEngine get engine {
    return _sessionController.value.engine!;
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    try {
      await _sessionController.initializeEngine(
          agoraConnectionData: agoraConnectionData);
    } catch (e) {
      log("Error while initializing Agora RTC SDK: $e",
          level: Level.error.value);
    }

    if (agoraConnectionData.rtmEnabled) {
      try {
        await _sessionController.initializeRtm(
            agoraRtmClientEventHandler ?? AgoraRtmClientEventHandler());
      } catch (e) {
        log("Error while initializing Agora RTM SDK. ${e.toString()}",
            level: Level.error.value);
      }
    }

    if (agoraChannelData?.clientRoleType ==
            ClientRoleType.clientRoleBroadcaster ||
        agoraChannelData?.clientRoleType == null) {
      await _sessionController.askForUserCameraAndMicPermission();
    }
    if (enabledPermission != null) {
      await enabledPermission!.request();
    }

    _sessionController.createEvents(
      agoraRtmChannelEventHandler ?? AgoraRtmChannelEventHandler(),
      agoraEventHandlers ?? AgoraRtcEventHandlers(),
    );

    if (agoraChannelData != null) {
      _sessionController.setChannelProperties(agoraChannelData!);
    }

    await _sessionController.joinVideoChannel();
    _initialized = true;

    if (cloudStorageData != null) {
      await initializeCloudRecording();
    }
  }

  Future<void> release() async {
    _initialized = false;
    await endCall(sessionController: _sessionController);
  }

  Future<void> initializeCloudRecording() async {
    //create credential
    String credentials =
        "${cloudStorageData!.customerKey}:${cloudStorageData!.customerSecret}";
    _cloudRecordingCredential = base64Encode(utf8.encode(credentials));
  }

  Future<String> generateResourceId() async {
    var headers = {
      'Authorization': 'basic $_cloudRecordingCredential',
      'Content-Type': 'application/json',
    };

    var url = Uri.parse(
        'https://api.agora.io/v1/apps/${agoraConnectionData.appId}/cloud_recording/acquire');

    var body = json.encode({
      "cname": agoraConnectionData.channelName,
      "uid": cloudRecordingId,
      "clientRequest": {}
    });

    http.Response response = await http.post(url, headers: headers, body: body);
    var decodedResponse = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    String resourceId = "";
    if (response.statusCode == 200) {
      resourceId = decodedResponse["resourceId"];
    } else {
      throw (response.reasonPhrase.toString());
    }
    _cloudRecordingResourceId = resourceId;
    return resourceId;
  }
}
