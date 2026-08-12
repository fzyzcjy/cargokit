import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import 'android_environment.dart';
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
    final targets = _targets();
    final environment = BuildEnvironment.fromEnvironment(isAndroid: true);
    final provider = ArtifactProvider(
      environment: environment,
      userOptions: userOptions,
    );
    final artifacts = await provider.getArtifacts(targets);

    for (final target in targets) {
      _copyTargetLibraries(
        target: target,
        libraries: artifacts[target]!,
        environment: environment,
      );
    }
  }

  List<Target> _targets() {
    return Environment.targetPlatforms
        .map((platform) {
          final target = Target.forFlutterName(platform);
          if (target == null) {
            throw Exception('Unknown Android target platform: $platform');
          }
          return target;
        })
        .toSet()
        .toList();
  }

  void _copyTargetLibraries({
    required Target target,
    required List<Artifact> libraries,
    required BuildEnvironment environment,
  }) {
    final outputDir = path.join(Environment.outputDir, target.android!);
    Directory(outputDir).createSync(recursive: true);
    final outputLibraries = _copyDynamicLibraries(libraries, outputDir);
    final androidEnvironment = AndroidEnvironment(
      sdkPath: environment.androidSdkPath!,
      ndkVersion: environment.androidNdkVersion!,
      minSdkVersion: environment.androidMinSdkVersion!,
      targetTempDir: environment.targetTempDir,
      target: target,
    );
    copyLibCppSharedIfNeeded(
      environment: androidEnvironment,
      nativeLibraries: outputLibraries,
      outputDir: outputDir,
    );
  }

  List<File> _copyDynamicLibraries(List<Artifact> libraries, String outputDir) {
    return libraries
        .where((library) => library.type == AritifactType.dylib)
        .map((library) {
      final output = File(path.join(outputDir, library.finalFileName));
      return File(library.path).copySync(output.path);
    }).toList();
  }
}
