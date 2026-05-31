/// Icon utilities for the app.
///
/// phosphor_flutter is installed. Use PhosphorIcons for all Material icon
/// replacements. Duotone style gives the best "premium" look.
///
/// Usage examples:
///   PhosphorIcon(PhosphorIcons.mapPin(), size: 22, color: primary)
///   PhosphorIcon(PhosphorIcons.heart(PhosphorIconsStyle.fill), color: error)
///   PhosphorIcon(PhosphorIcons.calendar(PhosphorIconsStyle.duotone))
///
/// For emoji replacement (🗺️ 🍜 etc.), two options:
///
/// Option A — Keep Text emoji but wrap in SizedBox with fixed size:
///   SizedBox(width: 24, height: 24,
///     child: Text('🗺️', style: TextStyle(fontSize: 20)))
///
/// Option B — SVG from Iconscout / Flaticon (best quality):
///   1. Download a pastel/3D icon pack as SVG
///   2. Put files in assets/icons/
///   3. Use: SvgPicture.asset('assets/icons/map.svg', width: 24, height: 24)
///
/// Option C — Lottie micro-animation on tap (most impressive):
///   1. Download from lordicon.com (free tier available)
///   2. Use: Lottie.asset('assets/lottie/heart.json',
///               controller: _ctrl, width: 32, height: 32)

// No actual code needed here — this is a documentation/guide file.
// Import phosphor_flutter wherever you want premium icons:
//   import 'package:phosphor_flutter/phosphor_flutter.dart';
