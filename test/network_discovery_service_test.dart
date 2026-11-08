import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_control_center/services/adb_service.dart';
import 'package:pixel_control_center/services/network_discovery_service.dart';

void main() {
  group('NetworkDiscoveryService parsing & multi-port discovery', () {
    late NetworkDiscoveryService discovery;

    setUp(() {
      discovery = NetworkDiscoveryService(adbService: AdbService());
    });

    test('preserves dynamic Android 11+ Wireless Debugging mDNS port and skips pairing port', () {
      const sampleMdns = '''
List of discovered mdns services
adb-28301FDH300557-k9x2p1\t_adb-tls-pairing._tcp.\t10.29.128.166:37199
adb-28301FDH300557-k9x2p1\t_adb-tls-connect._tcp.\t10.29.128.166:41823
adb-R5CW21ABCD-a1b2c3\t_adb._tcp.\t192.168.1.24:5555
''';

      final peers = discovery.parseMdnsServicesOutput(sampleMdns);
      expect(peers.length, 2);
      expect(peers[0].ip, '10.29.128.166');
      expect(peers[0].adbPort, 41823);
      expect(peers[1].ip, '192.168.1.24');
      expect(peers[1].adbPort, 5555);
    });

    test('extracts Default Gateway from French and English ipconfig output', () {
      const sampleFrIpconfig = '''
Carte réseau sans fil Wi-Fi :

   Adresse IPv4. . . . . . . . . . . . . .: 10.29.128.42
   Masque de sous-réseau. . . . . . . . . : 255.255.255.0
   Passerelle par défaut. . . . . . . . . : 10.29.128.223
''';

      final gateways = discovery.parseDefaultGateways(
        sampleFrIpconfig,
        allowedPrefixes: {'10.29.128'},
      );
      expect(gateways, contains('10.29.128.223'));
    });

    test('extracts valid unicast ARP neighbors while ignoring multicast and broadcast', () {
      const sampleArp = '''
Interface : 10.29.128.42 --- 0x12
  Adresse Internet      Adresse physique      Type
  10.29.128.44          f2-7c-cf-5f-01-8f     dynamique
  10.29.128.166         a6-1e-f1-af-ca-78     dynamique
  10.29.128.223         66-4d-a8-25-a1-1b     dynamique
  10.29.128.255         ff-ff-ff-ff-ff-ff     statique
  224.0.0.251           01-00-5e-00-00-fb     statique
  239.255.255.250       01-00-5e-7f-ff-fa     statique
  255.255.255.255       ff-ff-ff-ff-ff-ff     statique
''';

      final neighbors = discovery.parseArpNeighbors(
        sampleArp,
        allowedPrefixes: {'10.29.128'},
      );
      expect(
        neighbors,
        containsAll(['10.29.128.44', '10.29.128.166', '10.29.128.223']),
      );
      expect(neighbors, isNot(contains('10.29.128.255')));
      expect(neighbors, isNot(contains('224.0.0.251')));
      expect(neighbors, isNot(contains('239.255.255.250')));
    });
  });
}
