import 'package:bodyline_core/bodyline_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/body_panel_prefs.dart';

/// Body-map SVG (v2 organ set) with fills driven by live flags.
///
/// Geometry from `assets/brand/vitalog-body-map-organs.html`.
/// Only systems present in [flags] and [BodyPanelPrefs.glyphCodes] are painted;
/// others are omitted (hidden in customize).
class BodyMapView extends StatelessWidget {
  const BodyMapView({
    super.key,
    required this.flags,
    this.width = 150,
    this.height = 250,
    /// Profile sex: `m` / `f` / `male` / `female` — controls prostate vs uterus glyphs.
    this.sex,
  });

  final Map<String, ObservationFlag?> flags;
  final double width;
  final double height;
  final String? sex;

  static const _bodyFill = '#EDE3D8';
  static const _untested = '#D6CBBD';
  static const _ok = '#0E6B63';
  static const _high = '#B8561B';
  static const _low = '#2A5CA0';

  static const _bodyPath =
      'M91,40 L96,40 C97,50 99,56 108,60 C120,64 131,66 134,78 C137,96 139,120 142,150 C143,162 146,172 147,182 C149,192 147,200 142,200 C138,200 137,194 137,186 C135,170 131,150 129,134 C127,120 126,108 125,98 C123,112 120,126 119,140 C119,152 124,162 124,178 C124,200 118,230 116,262 C115,274 116,282 119,288 C121,293 117,296 110,296 C104,296 103,292 103,286 C103,268 101,236 97,212 C95,200 93,194 91,192 Z';

  bool get _isMale {
    final s = (sex ?? '').trim().toLowerCase();
    if (s.isEmpty) return true; // default male figure (matches HTML demo)
    if (s.startsWith('f') || s == 'female' || s == 'woman') return false;
    return true;
  }

  bool _active(String code) =>
      flags.containsKey(code) && BodyPanelPrefs.glyphCodes.contains(code);

  /// Fill/stroke for solid shapes (`.s`) and line organs (`.ln`).
  String _tone(String code) {
    if (!_active(code)) return _bodyFill;
    final flag = flags[code];
    if (flag == null) return _untested;
    switch (flag) {
      case ObservationFlag.normal:
        return _ok;
      case ObservationFlag.high:
      case ObservationFlag.criticalHigh:
      case ObservationFlag.abnormal:
        return _high;
      case ObservationFlag.low:
      case ObservationFlag.criticalLow:
        return _low;
    }
  }

  bool _attention(String code) {
    if (!_active(code)) return false;
    final f = flags[code];
    return f != null && f != ObservationFlag.normal;
  }

  String _halo(String code) {
    if (!_attention(code)) return '0';
    return '0.16';
  }

  String _haloFill(String code) {
    final f = flags[code];
    if (f == ObservationFlag.low || f == ObservationFlag.criticalLow) {
      return _low;
    }
    return _high;
  }

  String buildSvg() {
    final mirror = 'transform="matrix(-1 0 0 1 180 0)"';
    final outline = _bodyPath
        .replaceFirst('M91,40 L96,40 ', 'M96,40 ')
        .replaceFirst(' Z', '');

    String g(String code, String inner) {
      if (!_active(code)) return '';
      return '<g id="sys-$code" data-code="$code">$inner</g>';
    }

    String s(String code, String d) =>
        '<path d="$d" fill="${_tone(code)}"/>';

    String ln(String code, String d, {String extra = ''}) =>
        '<path d="$d" fill="none" stroke="${_tone(code)}" $extra/>';

    final generalDash = (flags['general'] == ObservationFlag.normal)
        ? ''
        : 'stroke-dasharray="3 2.2"';

    final reproductive = _isMale
        ? '''
<circle cx="90" cy="188" r="6" fill="${_haloFill('reproductive')}" opacity="${_halo('reproductive')}"/>
<ellipse cx="87.4" cy="188.4" rx="1.9" ry="2.4" fill="${_tone('reproductive')}"/>
<ellipse cx="92.6" cy="188.4" rx="1.9" ry="2.4" fill="${_tone('reproductive')}"/>
'''
        : '''
<circle cx="90" cy="177" r="13" fill="${_haloFill('reproductive')}" opacity="${_halo('reproductive')}"/>
${ln('reproductive', 'M85.5,173.6 C83.5,171.5 81.5,171.3 79.6,172.4 M94.5,173.6 C96.5,171.5 98.5,171.3 100.4,172.4', extra: 'stroke-width="1.2" stroke-linecap="round"')}
${s('reproductive', 'M90,186 C87,186 86,181 85.2,177.4 C84.4,173.6 86.6,171.6 90,172.2 C93.4,171.6 95.6,173.6 94.8,177.4 C94,181 93,186 90,186 Z')}
<ellipse cx="78.6" cy="173.4" rx="2.6" ry="2" fill="${_tone('reproductive')}"/>
<ellipse cx="101.4" cy="173.4" rx="2.6" ry="2" fill="${_tone('reproductive')}"/>
''';

    final prostate = _isMale
        ? g(
            'prostate',
            '''
<circle cx="90" cy="181" r="6.5" fill="${_haloFill('prostate')}" opacity="${_halo('prostate')}"/>
${s('prostate', 'M90,177.6 C93.2,177.6 94.2,179.8 93.7,182 C93.1,184.2 91.5,185 90,185 C88.5,185 86.9,184.2 86.3,182 C85.8,179.8 86.8,177.6 90,177.6 Z')}
''',
          )
        : '';

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 180 300" width="180" height="300" role="img" aria-label="Body map with tested areas highlighted">
  <g id="body">
    <ellipse cx="90" cy="292" rx="44" ry="5" fill="#E6E0D5"/>
    <ellipse cx="90" cy="24" rx="16" ry="19" fill="$_bodyFill"/>
    <path d="$_bodyPath" fill="$_bodyFill"/>
    <path d="$_bodyPath" fill="$_bodyFill" $mirror/>
  </g>
  ${g('general', '''
    ${ln('general', 'M84,41.6 A16.8,19.8 0 1 1 96,41.6', extra: 'stroke-width="1.1" $generalDash')}
    ${ln('general', outline, extra: 'stroke-width="1.1" $generalDash')}
    ${ln('general', outline, extra: 'stroke-width="1.1" $generalDash $mirror')}
    ${ln('general', 'M89,192 L91,192', extra: 'stroke-width="1.1"')}
  ''')}
  ${g('lungs', '''
    ${s('lungs', 'M77,73 C70,79 67,92 68,104 C69,111 77,111 81,106 C84,99 84,85 82,76 C81,71 79,71 77,73 Z')}
    ${s('lungs', 'M103,73 C110,79 113,92 112,104 C111,111 103,111 99,106 C96,99 96,85 98,76 C99,71 101,71 103,73 Z')}
  ''')}
  ${g('bones', '''
    <rect x="67" y="199" width="13" height="48" rx="6.5" fill="${_haloFill('bones')}" opacity="${_halo('bones')}" transform="rotate(4 73 222)"/>
    <rect x="100" y="199" width="13" height="48" rx="6.5" fill="${_haloFill('bones')}" opacity="${_halo('bones')}" transform="rotate(-4 107 222)"/>
    <rect x="71" y="203" width="5" height="40" rx="2.5" fill="${_tone('bones')}" transform="rotate(4 73 222)"/>
    <rect x="104" y="203" width="5" height="40" rx="2.5" fill="${_tone('bones')}" transform="rotate(-4 107 222)"/>
    <rect x="130" y="86" width="4.4" height="36" rx="2.2" fill="${_tone('bones')}" transform="rotate(-7 132 104)"/>
    <rect x="45.6" y="86" width="4.4" height="36" rx="2.2" fill="${_tone('bones')}" transform="rotate(7 48 104)"/>
  ''')}
  ${g('blood', '''
    ${ln('blood', 'M134,134 C136,148 138,161 141,176', extra: 'stroke-width="2.2" stroke-linecap="round"')}
    ${ln('blood', 'M136.5,147 C139.5,150 141,152 142.5,156', extra: 'stroke-width="1.4" stroke-linecap="round"')}
    ${ln('blood', 'M46,134 C44,148 42,161 39,176', extra: 'stroke-width="2.2" stroke-linecap="round"')}
    ${ln('blood', 'M43.5,147 C40.5,150 39,152 37.5,156', extra: 'stroke-width="1.4" stroke-linecap="round"')}
    ${s('blood', 'M135,124 C135,124 131.5,128.5 131.5,130.6 C131.5,132.6 133.1,134 135,134 C136.9,134 138.5,132.6 138.5,130.6 C138.5,128.5 135,124 135,124 Z')}
  ''')}
  ${g('heart', '''
    <circle cx="93" cy="95" r="15" fill="${_haloFill('heart')}" opacity="${_halo('heart')}"/>
    ${s('heart', 'M93,104 C85,98 83,90 88,87 C91,85 93,88 93,90 C93,88 95,85 98,87 C103,90 101,98 93,104 Z')}
  ''')}
  ${g('liver', '''
    <ellipse cx="82" cy="112" rx="22" ry="12" fill="${_haloFill('liver')}" opacity="${_halo('liver')}"/>
    ${s('liver', 'M66,110 C76,104 96,104 100,110 C96,116 84,119 72,119 C64,118 63,113 66,110 Z')}
  ''')}
  ${g('immune', '''
    <ellipse cx="114.6" cy="108.4" rx="7" ry="8" fill="${_haloFill('immune')}" opacity="${_halo('immune')}"/>
    ${s('immune', 'M112,103 C115.5,101.6 118.4,104.5 117.6,109 C116.9,112.6 114,114.8 111.8,113.4 C113.3,110.4 113.4,106.6 112,103 Z')}
    <circle cx="85.6" cy="42.6" r="1.3" fill="${_tone('immune')}"/>
    <circle cx="94.4" cy="42.6" r="1.3" fill="${_tone('immune')}"/>
    <circle cx="120.5" cy="84" r="1.5" fill="${_tone('immune')}"/>
    <circle cx="122" cy="89" r="1.3" fill="${_tone('immune')}"/>
    <circle cx="59.5" cy="84" r="1.5" fill="${_tone('immune')}"/>
    <circle cx="58" cy="89" r="1.3" fill="${_tone('immune')}"/>
    <circle cx="79" cy="183" r="1.5" fill="${_tone('immune')}"/>
    <circle cx="81.5" cy="187" r="1.3" fill="${_tone('immune')}"/>
    <circle cx="101" cy="183" r="1.5" fill="${_tone('immune')}"/>
    <circle cx="98.5" cy="187" r="1.3" fill="${_tone('immune')}"/>
  ''')}
  ${g('pancreas', '''
    <ellipse cx="97" cy="121.5" rx="18" ry="8" fill="${_haloFill('pancreas')}" opacity="${_halo('pancreas')}"/>
    ${s('pancreas', 'M84,121 C90,117 101,116.5 108,118 C112,119.5 111,124 106,124.8 C98,126 90,126 86,125 C82,124 82,122 84,121 Z')}
  ''')}
  ${g('kidney', '''
    <ellipse cx="78" cy="136" rx="9" ry="12" fill="${_haloFill('kidney')}" opacity="${_halo('kidney')}"/>
    <ellipse cx="102" cy="136" rx="9" ry="12" fill="${_haloFill('kidney')}" opacity="${_halo('kidney')}"/>
    ${s('kidney', 'M78,128 C74,129 73,136 75,141 C77,145 82,144 82,140 C80,137 80,133 82,131 C82,128 80,127 78,128 Z')}
    ${s('kidney', 'M102,128 C106,129 107,136 105,141 C103,145 98,144 98,140 C100,137 100,133 98,131 C98,128 100,127 102,128 Z')}
  ''')}
  ${g('adrenal', '''
    ${s('adrenal', 'M74,126.6 L78.2,121 L82.6,125.4 C80,127.4 77,127.6 74,126.6 Z')}
    ${s('adrenal', 'M106,126.6 L101.8,121 L97.4,125.4 C100,127.4 103,127.6 106,126.6 Z')}
  ''')}
  ${g('thyroid', '''
    <ellipse cx="90" cy="50" rx="12" ry="7" fill="${_haloFill('thyroid')}" opacity="${_halo('thyroid')}"/>
    ${s('thyroid', 'M90,50 C87,46 82,46 82,50 C82,54 87,54 90,51 C93,54 98,54 98,50 C98,46 93,46 90,50 Z')}
  ''')}
  ${g('parathyroid', '''
    <circle cx="80.6" cy="47.2" r="1.35" fill="${_tone('parathyroid')}"/>
    <circle cx="80.6" cy="52.8" r="1.35" fill="${_tone('parathyroid')}"/>
    <circle cx="99.4" cy="47.2" r="1.35" fill="${_tone('parathyroid')}"/>
    <circle cx="99.4" cy="52.8" r="1.35" fill="${_tone('parathyroid')}"/>
  ''')}
  ${g('pituitary', '''
    <circle cx="90" cy="26" r="6" fill="${_haloFill('pituitary')}" opacity="${_halo('pituitary')}"/>
    ${ln('pituitary', 'M90,19 L90,23.5', extra: 'stroke-width="1" stroke-linecap="round"')}
    <ellipse cx="90" cy="26" rx="2.8" ry="2.4" fill="${_tone('pituitary')}"/>
  ''')}
  $prostate
  ${g('reproductive', reproductive)}
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
