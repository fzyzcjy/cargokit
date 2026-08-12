import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:path/path.dart' as path;
import 'package:version/version.dart';

import 'target.dart';
import 'util.dart';

class AndroidEnvironment {
  AndroidEnvironment({
    required this.sdkPath,
    required this.ndkVersion,
    required this.minSdkVersion,
    required this.targetTempDir,
    required this.target,
    this.hostTag,
  });

  static void clangLinkerWrapper(List<String> args) {
    final clang = Platform.environment['_CARGOKIT_NDK_LINK_CLANG'];
    if (clang == null) {
      throw Exception(
        "cargo-ndk rustc linker: didn't find _CARGOKIT_NDK_LINK_CLANG env var",
      );
    }
    final target = Platform.environment['_CARGOKIT_NDK_LINK_TARGET'];
    if (target == null) {
      throw Exception(
        "cargo-ndk rustc linker: didn't find _CARGOKIT_NDK_LINK_TARGET env var",
      );
    }

    runCommand(clang, [target, ...args]);
  }

  /// Full path to Android SDK.
  final String sdkPath;

  /// Full version of Android NDK.
  final String ndkVersion;

  /// Minimum supported SDK version.
  final int minSdkVersion;

  /// Target directory for build artifacts.
  final String targetTempDir;

  /// Target being built.
  final Target target;

  /// NDK prebuilt host tag. Tests may set this to model a supported host.
  final String? hostTag;

  String get _hostTag => hostTag ?? _hostTagForCurrentPlatform();

  static String _hostTagForCurrentPlatform() {
    return switch (Abi.current()) {
      Abi.linuxX64 => 'linux-x86_64',
      Abi.macosArm64 => 'darwin-arm64',
      Abi.macosX64 => 'darwin-x86_64',
      Abi.windowsX64 => 'windows-x86_64',
      _ => throw UnsupportedError(
          'Unsupported Android NDK host ABI: ${Abi.current()}',
        ),
    };
  }

  String get _toolchainPath {
    return path.join(
      sdkPath,
      'ndk',
      ndkVersion,
      'toolchains',
      'llvm',
      'prebuilt',
      _hostTag,
    );
  }

  bool ndkIsInstalled() {
    final ndkPath = path.join(sdkPath, 'ndk', ndkVersion);
    final ndkPackageXml = File(path.join(ndkPath, 'package.xml'));
    return ndkPackageXml.existsSync();
  }

  void installNdk({required String javaHome}) {
    final sdkManagerExtension = Platform.isWindows ? '.bat' : '';
    final sdkManager = path.join(
      sdkPath,
      'cmdline-tools',
      'latest',
      'bin',
      'sdkmanager$sdkManagerExtension',
    );

    log.info('Installing NDK $ndkVersion');
    runCommand(
      sdkManager,
      ['--install', 'ndk;$ndkVersion'],
      environment: {'JAVA_HOME': javaHome},
    );
  }

  Future<Map<String, String>> buildEnvironment() async {
    final toolchainPath = path.join(_toolchainPath, 'bin');

    final minSdkVersion = math.max(
      target.androidMinSdkVersion!,
      this.minSdkVersion,
    );

    final exe = Platform.isWindows ? '.exe' : '';

    final arKey = 'AR_${target.rust}';
    final arValue = ['${target.rust}-ar', 'llvm-ar', 'llvm-ar.exe']
        .map((e) => path.join(toolchainPath, e))
        .firstWhereOrNull((element) => File(element).existsSync());
    if (arValue == null) {
      throw Exception('Failed to find ar for $target in $toolchainPath');
    }

    final targetArg = '--target=${target.rust}$minSdkVersion';

    final ccKey = 'CC_${target.rust}';
    final ccValue = path.join(toolchainPath, 'clang$exe');
    final cfFlagsKey = 'CFLAGS_${target.rust}';
    final cFlagsValue = targetArg;

    final cxxKey = 'CXX_${target.rust}';
    final cxxValue = path.join(toolchainPath, 'clang++$exe');
    final cxxFlagsKey = 'CXXFLAGS_${target.rust}';
    final cxxFlagsValue = targetArg;

    final linkerKey =
        'cargo_target_${target.rust.replaceAll('-', '_')}_linker'.toUpperCase();

    final ranlibKey = 'RANLIB_${target.rust}';
    final ranlibValue = path.join(toolchainPath, 'llvm-ranlib$exe');

    final ndkVersionParsed = Version.parse(ndkVersion);
    final rustFlagsKey = 'CARGO_ENCODED_RUSTFLAGS';
    final rustFlagsValue = _libGccWorkaround(targetTempDir, ndkVersionParsed);

    final runRustTool =
        Platform.isWindows ? 'run_build_tool.cmd' : 'run_build_tool.sh';

    final packagePath = (await Isolate.resolvePackageUri(
      Uri.parse('package:build_tool/buildtool.dart'),
    ))!
        .toFilePath();
    final selfPath = path.canonicalize(
      path.join(packagePath, '..', '..', '..', runRustTool),
    );

    // Make sure that run_build_tool is working properly even initially launched directly
    // through dart run.
    final toolTempDir =
        Platform.environment['CARGOKIT_TOOL_TEMP_DIR'] ?? targetTempDir;

    return {
      arKey: arValue,
      ccKey: ccValue,
      cfFlagsKey: cFlagsValue,
      cxxKey: cxxValue,
      cxxFlagsKey: cxxFlagsValue,
      ranlibKey: ranlibValue,
      rustFlagsKey: rustFlagsValue,
      linkerKey: selfPath,
      // Recognized by main() so we know when we're acting as a wrapper
      '_CARGOKIT_NDK_LINK_TARGET': targetArg,
      '_CARGOKIT_NDK_LINK_CLANG': ccValue,
      'CARGOKIT_TOOL_TEMP_DIR': toolTempDir,
    };
  }

  // Workaround for libgcc missing in NDK23, inspired by cargo-ndk
  String _libGccWorkaround(String buildDir, Version ndkVersion) {
    final workaroundDir = path.join(
      buildDir,
      'cargokit',
      'libgcc_workaround',
      '${ndkVersion.major}',
    );
    Directory(workaroundDir).createSync(recursive: true);
    if (ndkVersion.major >= 23) {
      File(
        path.join(workaroundDir, 'libgcc.a'),
      ).writeAsStringSync('INPUT(-lunwind)');
    } else {
      // Other way around, untested, forward libgcc.a from libunwind once Rust
      // gets updated for NDK23+.
      File(
        path.join(workaroundDir, 'libunwind.a'),
      ).writeAsStringSync('INPUT(-lgcc)');
    }

    var rustFlags = Platform.environment['CARGO_ENCODED_RUSTFLAGS'] ?? '';
    if (rustFlags.isNotEmpty) {
      rustFlags = '$rustFlags\x1f';
    }
    if (["arm64-v8a", "x86_64"].contains(target.android)) {
      rustFlags = '$rustFlags-L\x1f$workaroundDir\x1f';

      const pageSizeArgs = [
        "-C",
        "link-arg=-Wl,--hash-style=both",
        "-C",
        "link-arg=-Wl,-z,max-page-size=16384",
      ];
      final pageSizeArgsString = pageSizeArgs.join("\x1f");

      rustFlags = '$rustFlags$pageSizeArgsString';
    } else {
      rustFlags = '$rustFlags-L\x1f$workaroundDir';
    }
    return rustFlags;
  }
}

/// Copies the matching NDK C++ runtime only when an output library needs it.
void copyLibCppSharedIfNeeded({
  required AndroidEnvironment environment,
  required Iterable<File> nativeLibraries,
  required String outputDir,
}) {
  if (!nativeLibraries
      .any((library) => needsLibCppShared(environment, library))) {
    return;
  }

  final source = File(libCppSharedPath(environment));
  if (!source.existsSync()) {
    throw StateError(
      'Failed to find libc++_shared.so for '
      '${environment.target.android} at ${source.path}',
    );
  }
  source.copySync(path.join(outputDir, source.uri.pathSegments.last));
}

/// NDK sysroot path for the C++ runtime of this Android ABI.
String libCppSharedPath(AndroidEnvironment environment) {
  return path.join(
    environment._toolchainPath,
    'sysroot',
    'usr',
    'lib',
    environment.target.androidNdkTriple,
    'libc++_shared.so',
  );
}

bool needsLibCppShared(AndroidEnvironment environment, File nativeLibrary) {
  final readElf = path.join(
    environment._toolchainPath,
    'bin',
    'llvm-readelf${Platform.isWindows ? '.exe' : ''}',
  );
  final output = runCommand(readElf, ['--dynamic', nativeLibrary.path]).stdout;
  return hasLibCppSharedDependency(output.toString());
}

bool hasLibCppSharedDependency(String dynamicSection) {
  return RegExp(r'\(NEEDED\).*\[libc\+\+_shared\.so\]')
      .hasMatch(dynamicSection);
}
