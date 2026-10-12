import 'package:bodyline_core/bodyline_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/body_panel_prefs.dart';

/// Body-map SVG with organ fills driven by live flags.
///
/// Only systems present in [flags] are painted as status colors; others blend
/// into the silhouette (caller should pass [BodyPanelPrefs.mapFlags]).
class BodyMapView extends StatelessWidget {
  const BodyMapView({
    super.key,
    required this.flags,
    this.width = 150,
    this.height = 250,
  });

  final Map<String, ObservationFlag?> flags;
  final double width;
  final double height;

  static const _bodyFill = '#EDE3D8';
  static const _hiddenFill = '#EDE3D8';

  static String _organFill(ObservationFlag? flag, {required bool active}) {
    if (!active) return _hiddenFill;
    if (flag == null) return '#E3D9CC';
    switch (flag) {
      case ObservationFlag.normal:
        return '#0E6B63';
      case ObservationFlag.high:
      case ObservationFlag.criticalHigh:
      case ObservationFlag.abnormal:
        return '#B8561B';
      case ObservationFlag.low:
      case ObservationFlag.criticalLow:
        return '#2A5CA0';
    }
  }

  static bool _isAttention(ObservationFlag? flag, {required bool active}) {
    if (!active) return false;
    if (flag == null || flag == ObservationFlag.normal) return false;
    return true;
  }

  bool _active(String code) =>
      flags.containsKey(code) && BodyPanelPrefs.glyphCodes.contains(code);

  String buildSvg() {
    final thyroid = _organFill(flags['thyroid'], active: _active('thyroid'));
    final heart = _organFill(flags['heart'], active: _active('heart'));
    final liver = _organFill(flags['liver'], active: _active('liver'));
    final kidney = _organFill(flags['kidney'], active: _active('kidney'));
    final lungs = _organFill(flags['lungs'], active: _active('lungs'));
    final pancreas = _organFill(flags['pancreas'], active: _active('pancreas'));
    final bone = _organFill(flags['bone'], active: _active('bone'));

    final heartHalo = _isAttention(flags['heart'], active: _active('heart'));
    final boneHalo = _isAttention(flags['bone'], active: _active('bone'));
    final pancreasHalo =
        _isAttention(flags['pancreas'], active: _active('pancreas'));

    final headUntested = !_active('thyroid') || flags['thyroid'] == null;

    final headMark = headUntested
        ? '<ellipse cx="90" cy="21" rx="10" ry="8" fill="none" stroke="#9A968C" stroke-width="1.3" stroke-dasharray="3 2.5"/>'
        : '';
    final heartHaloSvg = heartHalo
        ? '<circle cx="93" cy="95" r="15" fill="$heart" opacity="0.14"/><circle cx="93" cy="95" r="10" fill="$heart" opacity="0.14"/>'
        : '';
    final pancreasHaloSvg = pancreasHalo
        ? '<ellipse cx="96" cy="126" rx="16" ry="7" fill="$pancreas" opacity="0.12"/>'
        : '';
    final boneHaloSvg = boneHalo
        ? '<rect x="66" y="198" width="15" height="50" rx="7.5" fill="$bone" opacity="0.14" transform="rotate(4 73 222)"/><rect x="99" y="198" width="15" height="50" rx="7.5" fill="$bone" opacity="0.14" transform="rotate(-4 107 222)"/>'
        : '';

    return '''
<svg width="180" height="300" viewBox="0 0 180 300" xmlns="http://www.w3.org/2000/svg" aria-label="Body map with tested areas highlighted">
  <ellipse cx="90" cy="292" rx="44" ry="5" fill="#E6E0D5"/>
  <ellipse cx="90" cy="24" rx="16" ry="19" fill="$_bodyFill"/>
  <path d="M91,40 L96,40 C97,50 99,56 108,60 C120,64 131,66 134,78 C137,96 139,120 142,150 C143,162 146,172 147,182 C149,192 147,200 142,200 C138,200 137,194 137,186 C135,170 131,150 129,134 C127,120 126,108 125,98 C123,112 120,126 119,140 C119,152 124,162 124,178 C124,200 118,230 116,262 C115,274 116,282 119,288 C121,293 117,296 110,296 C104,296 103,292 103,286 C103,268 101,236 97,212 C95,200 93,194 91,192 Z" fill="$_bodyFill"/>
  <path d="M91,40 L96,40 C97,50 99,56 108,60 C120,64 131,66 134,78 C137,96 139,120 142,150 C143,162 146,172 147,182 C149,192 147,200 142,200 C138,200 137,194 137,186 C135,170 131,150 129,134 C127,120 126,108 125,98 C123,112 120,126 119,140 C119,152 124,162 124,178 C124,200 118,230 116,262 C115,274 116,282 119,288 C121,293 117,296 110,296 C104,296 103,292 103,286 C103,268 101,236 97,212 C95,200 93,194 91,192 Z" fill="$_bodyFill" transform="matrix(-1 0 0 1 180 0)"/>
  $headMark
  <path id="thyroid" d="M90,50 C87,46 82,46 82,50 C82,54 87,54 90,51 C93,54 98,54 98,50 C98,46 93,46 90,50 Z" fill="$thyroid"/>
  <path id="lungs-left" d="M77,73 C70,79 67,92 68,104 C69,111 77,111 81,106 C84,99 84,85 82,76 C81,71 79,71 77,73 Z" fill="$lungs"/>
  <path id="lungs-right" d="M103,73 C110,79 113,92 112,104 C111,111 103,111 99,106 C96,99 96,85 98,76 C99,71 101,71 103,73 Z" fill="$lungs"/>
  $heartHaloSvg
  <path id="heart" d="M93,104 C85,98 83,90 88,87 C91,85 93,88 93,90 C93,88 95,85 98,87 C103,90 101,98 93,104 Z" fill="$heart"/>
  <path id="liver" d="M69,112 C78,107 97,107 101,113 C97,120 85,124 73,123 C66,121 65,115 69,112 Z" fill="$liver" opacity="0.9"/>
  $pancreasHaloSvg
  <path id="pancreas" d="M82,124 C88,120 104,120 112,124 C114,126 112,129 106,130 C98,131 90,131 84,129 C80,127 80,125 82,124 Z" fill="$pancreas"/>
  <path id="kidney-left" d="M78,138 C74,139 73,146 75,151 C77,155 82,154 82,150 C80,147 80,143 82,141 C82,138 80,137 78,138 Z" fill="$kidney"/>
  <path id="kidney-right" d="M102,138 C106,139 107,146 105,151 C103,155 98,154 98,150 C100,147 100,143 98,141 C98,138 100,137 102,138 Z" fill="$kidney"/>
  $boneHaloSvg
  <rect id="bone-left" x="71" y="203" width="5" height="40" rx="2.5" fill="$bone" transform="rotate(4 73 222)"/>
  <rect id="bone-right" x="104" y="203" width="5" height="40" rx="2.5" fill="$bone" transform="rotate(-4 107 222)"/>
</svg>
''';
  }

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      buildSvg(),
      width: width,
      height: height,
      fit: BoxFit.contain,
    );
  }
}
