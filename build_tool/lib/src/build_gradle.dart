import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import 'artifacts_provider.dart';
import 'builder.dart';
import 'environment.dart';
import 'options.dart';
import 'target.dart';

final log = Logger('build_gradle');

class BuildGradle {
  BuildGradle({required this.userOptions});

  final CargokitUserOptions userOptions;

  Future<void> build() async {
    final targets = Environment.targetPlatforms
        .map((arch) {
          final target = Target.forFlutterName(arch);
          if (target == null) {
            throw Exception(
              "Unknown darwin target or platform: $arch, ${Environment.darwinPlatformName}",
            );
          }
          return target;
        })
        .toSet()
        .toList();

    final environment = BuildEnvironment.fromEnvironment(isAndroid: true);
    final provider = ArtifactProvider(
      environment: environment,
      userOptions: userOptions,
    );
    final artifacts = await provider.getArtifacts(targets);

    for (final target in targets) {
      final libs = artifacts[target]!;
      final outputDir = path.join(Environment.outputDir, target.android!);
      Directory(outputDir).createSync(recursive: true);

      for (final lib in libs) {
        if (lib.type == AritifactType.dylib) {
          File(lib.path).copySync(path.join(outputDir, lib.finalFileName));
        }
      }

      if (Environment.copyLibcxxShared) {
        final hostArch = Platform.isMacOS
            ? 'darwin-x86_64'
            : (Platform.isLinux ? 'linux-x86_64' : 'windows-x86_64');
        final ndkTarget = target.rust == 'armv7-linux-androideabi'
            ? 'arm-linux-androideabi'
            : target.rust;
        final cppRuntimePath = path.joinAll([
          Environment.sdkPath,
          'ndk',
          Environment.ndkVersion,
          'toolchains',
          'llvm',
          'prebuilt',
          hostArch,
          'sysroot',
          'usr',
          'lib',
          ndkTarget,
          'libc++_shared.so',
        ]);
        final cppRuntime = File(cppRuntimePath);
        if (!cppRuntime.existsSync()) {
          throw Exception('Android C++ runtime not found: $cppRuntimePath');
        }
        cppRuntime.copySync(path.join(outputDir, 'libc++_shared.so'));
      }
    }
  }
}
