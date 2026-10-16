/// Constants used throughout the tinytuya library
/// Ported from tinytuya/core/const.py

library;

// Globals Network Settings
const int maxCount = 15; // How many tries before stopping
const int scanTime =
    18; // How many seconds to wait before stopping device discovery
const int udpPort = 6666; // Tuya 3.1 UDP Port
const int udpPortS = 6667; // Tuya 3.3 encrypted UDP Port
const int udpPortApp = 7000; // Tuya app encrypted UDP Port
const int tcpPort = 6668; // Tuya TCP Local Port
const double timeout = 3.0; // Seconds to wait for a broadcast
const double tcpTimeout = 0.4; // Seconds to wait for socket open for scanning
const String defaultNetwork = '192.168.0.0/24';

// Configuration Files
const String configFile = 'tinytuya.json';
const String deviceFile = 'devices.json';
const String rawFile = 'tuya-raw.json';
const String snapshotFile = 'snapshot.json';

// Device file save values
const List<String> deviceFileSaveValues = [
  'category',
  'product_name',
  'product_id',
  'biz_type',
  'model',
  'sub',
  'icon',
  'version',
  'last_ip',
  'uuid',
  'node_id',
  'sn',
  'mapping',
];
