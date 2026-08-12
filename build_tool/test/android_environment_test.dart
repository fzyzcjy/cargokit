import 'dart:io';

import 'package:build_tool/src/android_environment.dart';
import 'package:build_tool/src/target.dart';
import 'package:build_tool/src/util.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory temporaryDirectory;
  late AndroidEnvironment environment;
  late File nativeLibrary;
  late File runtimeLibrary;
  late Directory outputDirectory;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync('cargokit-test-');
    environment = AndroidEnvironment(
      sdkPath: temporaryDirectory.path,
      ndkVersion: 'test-ndk',
      minSdkVersion: 21,
      targetTempDir: temporaryDirectory.path,
      target: Target.forFlutterName('android-arm64')!,
      hostTag: 'linux-x86_64',
    );
    nativeLibrary = File(path.join(temporaryDirectory.path, 'libnative.so'))
      ..writeAsStringSync('native');
    runtimeLibrary = File(
      path.joinAll([
        temporaryDirectory.path,
        'ndk',
        'test-ndk',
        'toolchains',
        'llvm',
        'prebuilt',
        'linux-x86_64',
        'sysroot',
        'usr',
        'lib',
        'aarch64-linux-android',
        'libc++_shared.so',
      ]),
    )
      ..createSync(recursive: true)
      ..writeAsStringSync('android-cxx-runtime');
    outputDirectory = Directory(path.join(temporaryDirectory.path, 'output'))
      ..createSync();
  });

  tearDown(() {
    testRunCommandOverride = null;
    temporaryDirectory.deleteSync(recursive: true);
  });

  test('copies ABI-matched C++ runtime when an output needs it', () {
    testRunCommandOverride = (args) {
      expect(args.arguments, ['--dynamic', nativeLibrary.path]);
      return TestRunCommandResult(
        stdout:
            '0x0000000000000001 (NEEDED) Shared library: [libc++_shared.so]',
      );
    };

    environment.copyLibCppSharedIfNeeded(
      nativeLibraries: [nativeLibrary],
      outputDir: outputDirectory.path,
    );

    final copiedRuntime = File(
      path.join(outputDirectory.path, 'libc++_shared.so'),
    );
    expect(copiedRuntime.readAsStringSync(), runtimeLibrary.readAsStringSync());
  });

  test('does not copy C++ runtime when no output needs it', () {
    testRunCommandOverride = (_) => TestRunCommandResult(
          stdout: '0x0000000000000001 (NEEDED) Shared library: [liblog.so]',
        );

    environment.copyLibCppSharedIfNeeded(
      nativeLibraries: [nativeLibrary],
      outputDir: outputDirectory.path,
    );

    expect(
      File(path.join(outputDirectory.path, 'libc++_shared.so')).existsSync(),
      isFalse,
    );
  });

  test('recognizes only an ELF DT_NEEDED libc++ runtime', () {
    expect(
      AndroidEnvironment.hasLibCppSharedDependency(
        '0x0000000000000001 (NEEDED) Shared library: [libc++_shared.so]',
      ),
      isTrue,
    );
    expect(
      AndroidEnvironment.hasLibCppSharedDependency(
        '0x000000000000000e (SONAME) Library soname: [libc++_shared.so]',
      ),
      isFalse,
    );
  });

  test('maps Android ABIs to their NDK sysroot directories', () {
    expect(
      Target.forFlutterName('android-arm')!.androidNdkTriple,
      'arm-linux-androideabi',
    );
    expect(
      Target.forFlutterName('android-arm64')!.androidNdkTriple,
      'aarch64-linux-android',
    );
    expect(
      Target.forFlutterName('android-x86')!.androidNdkTriple,
      'i686-linux-android',
    );
    expect(
      Target.forFlutterName('android-x64')!.androidNdkTriple,
      'x86_64-linux-android',
    );
  });
}
