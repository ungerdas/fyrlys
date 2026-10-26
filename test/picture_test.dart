import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/core/picture.dart';
import 'package:fyrlys/core/session.dart';
import 'package:fyrlys/ui/picture_dialogs.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  test('bildeformatene', () {
    expect(PictureFormat.parse('zoom'), PictureFormat.zoom);
    expect(PictureFormat.parse('noe annet'), PictureFormat.original);
    expect(PictureFormat.parse(null), PictureFormat.original);
    expect(PictureFormat.original.next, PictureFormat.zoom);
    expect(PictureFormat.classic.next, PictureFormat.original);
    expect(PictureFormat.wide.aspectRatio, 16 / 9);
    expect(PictureFormat.classic.aspectRatio, 4 / 3);
    expect(PictureFormat.zoom.aspectRatio, isNull);
    expect([for (final f in PictureFormat.values) formatName(f)], ['Original', 'Fyll skjermen', 'Strekk', '16:9', '4:3']);
  });

  test('lydforsinkelsen: steg på 50 ms, høyst 2 sekunder hver vei', () {
    expect(clampAudioDelay(const Duration(milliseconds: 123)), const Duration(milliseconds: 100));
    expect(clampAudioDelay(const Duration(milliseconds: 130)), const Duration(milliseconds: 150));
    expect(clampAudioDelay(const Duration(seconds: 3)), const Duration(seconds: 2));
    expect(clampAudioDelay(const Duration(milliseconds: -2600)), const Duration(seconds: -2));
    expect(audioDelayText(Duration.zero), '0 ms');
    expect(audioDelayText(const Duration(milliseconds: 250)), '+250 ms');
    expect(audioDelayText(const Duration(milliseconds: -1500)), '−1500 ms');
  });

  test('det som huskes for en kanal', () {
    const view = ChannelView(format: PictureFormat.wide, audioDelay: Duration(milliseconds: -200));
    expect(view.toJson(), {'f': 'wide', 'd': -200});
    expect(ChannelView.fromJson(view.toJson()), view);
    expect(const ChannelView().toJson(), isEmpty);
    expect(const ChannelView().isDefault, isTrue);
    expect(ChannelView.fromJson(null), const ChannelView());
    expect(ChannelView.fromJson({'f': 'zoom', 'd': 99999}).audioDelay, const Duration(seconds: 2));
  });

  test('per kanal og per innlogging', () async {
    SharedPreferences.setMockInitialValues({'source': '{"kind":"fake"}'});
    final s = Session(await SharedPreferences.getInstance(),
        sourceFactory: (saved) async => FakeSource(name: saved['name'] ?? 'Test'));
    await s.restore();
    final first = s.activeLogin!;
    const view = ChannelView(format: PictureFormat.zoom, audioDelay: Duration(milliseconds: 100));
    s.saveChannelView('101', view);
    expect(s.channelView('101'), view);
    expect(s.channelView('102'), const ChannelView());

    await s.useSource(FakeSource(name: 'Sport'));
    expect(s.channelView('101'), const ChannelView());
    await s.switchLogin(first);
    expect(s.channelView('101'), view);

    // tilbake til det vanlige: glemt
    s.saveChannelView('101', const ChannelView());
    expect(s.channelView('101'), const ChannelView());
  });
}
