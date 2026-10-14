import 'package:anilab/core/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PrimaryButton merender label & merespons tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PrimaryButton(label: 'Play', onPressed: () => taps++),
          ),
        ),
      ),
    );
    expect(find.text('Play'), findsOneWidget);
    await tester.tap(find.text('Play'));
    expect(taps, 1);
  });

  testWidgets('EmptyView menampilkan judul & aksi', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyView(
            icon: Icons.bookmark_border_rounded,
            title: 'Belum ada favorit',
            subtitle: 'Tambahkan dari beranda',
          ),
        ),
      ),
    );
    expect(find.text('Belum ada favorit'), findsOneWidget);
    expect(find.text('Tambahkan dari beranda'), findsOneWidget);
  });
}
