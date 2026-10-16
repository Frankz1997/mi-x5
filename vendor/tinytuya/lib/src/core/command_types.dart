/// Command type definitions for Tuya protocol
/// Ported from tinytuya/core/command_types.py
/// Reference: https://github.com/tuya/tuya-iotos-embeded-sdk-wifi-ble-bk7231n/blob/master/sdk/include/lan_protocol.h

library;

// Tuya Command Types
const int apConfig = 1; // FRM_TP_CFG_WF - only used for ap 3.0 network config
const int active = 2; // FRM_TP_ACTV (discard) - WORK_MODE_CMD
const int sessKeyNegStart = 3; // FRM_SECURITY_TYPE3 - negotiate session key
const int sessKeyNegResp =
    4; // FRM_SECURITY_TYPE4 - negotiate session key response
const int sessKeyNegFinish =
    5; // FRM_SECURITY_TYPE5 - finalize session key negotiation
const int unbind = 6; // FRM_TP_UNBIND_DEV - DATA_QUERT_CMD - issue command
const int control = 7; // FRM_TP_CMD - STATE_UPLOAD_CMD
const int status = 8; // FRM_TP_STAT_REPORT - STATE_QUERY_CMD
const int heartBeat = 9; // FRM_TP_HB
const int dpQuery =
    0x0a; // 10 - FRM_QUERY_STAT - UPDATE_START_CMD - get data points
const int queryWifi = 0x0b; // 11 - FRM_SSID_QUERY (discard) - UPDATE_TRANS_CMD
const int tokenBind =
    0x0c; // 12 - FRM_USER_BIND_REQ - GET_ONLINE_TIME_CMD - system time (GMT)
const int controlNew = 0x0d; // 13 - FRM_TP_NEW_CMD - FACTORY_MODE_CMD
const int enableWifi = 0x0e; // 14 - FRM_ADD_SUB_DEV_CMD - WIFI_TEST_CMD
const int wifiInfo = 0x0f; // 15 - FRM_CFG_WIFI_INFO
const int dpQueryNew = 0x10; // 16 - FRM_QUERY_STAT_NEW
const int sceneExecute = 0x11; // 17 - FRM_SCENE_EXEC
const int updatedps = 0x12; // 18 - FRM_LAN_QUERY_DP - Request refresh of DPS
const int udpNew = 0x13; // 19 - FR_TYPE_ENCRYPTION
const int apConfigNew = 0x14; // 20 - FRM_AP_CFG_WF_V40
const int boardcastLpv34 = 0x23; // 35 - FR_TYPE_BOARDCAST_LPV34
const int reqDevinfo =
    0x25; // broadcast to port 7000 to get v3.5 devices to send their info
const int lanExtStream = 0x40; // 64 - FRM_LAN_EXT_STREAM
