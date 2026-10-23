import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'recommended_journey_page.dart';
import 'navigation_page.dart';
import '../config/elmina_map_config.dart';
import '../services/app_language.dart';

/// Home entry for the indoor map and adaptive journey planner.
/// The background image is stored at assets/data/main_page_background.jpg.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static const Color _accent = Color(0xFF10B981);

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Keep the source image unmodified; Flutter applies the effect.
            Image.asset(
              'assets/data/main_page_background.jpg',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),

            // Transparent gradient improves readability without blurring the photo.
            Positioned.fill(
              child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x44091A2A),
                        Color(0x7707192C),
                        Color(0xB8051527),
                      ],
                      stops: [0.0, 0.48, 1.0],
                    ),
                  ),
              ),
            ),

            // Scroll as needed on smaller devices / landscape orientation.
            SafeArea(
              child: Stack(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 28,
                              ),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 400),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(28),
                                  child: BackdropFilter(
                                    // Subtle frosted-glass effect on this card only.
                                    filter: ImageFilter.blur(sigmaX: 2.0, sigmaY: 2.0),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 34,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0x29FFFFFF),
                                        borderRadius: BorderRadius.circular(28),
                                        border: Border.all(
                                          color: const Color(0x55FFFFFF),
                                          width: 1,
                                        ),
                                      ),
                                      child: ValueListenableBuilder<AppLang>(
                                        valueListenable: AppLanguage.current,
                                        builder: (context, _, __) {
                                          return Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Center(
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(18),
                                                  child: Image.asset(
                                                    'assets/data/mallpilot_home_logo.png',
                                                    width: 78,
                                                    height: 78,
                                                    fit: BoxFit.contain,
                                                    semanticLabel: 'MallPilot logo',
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 14),
                                              const Text(
                                                'MallPilot',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 36,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 0.2,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                AppLanguage.t('slogan'),
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  color: Color(0xE8FFFFFF),
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              Text(
                                                AppLanguage.t('sub_tag'),
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: 0.3,
                                                  color: Color(0xEEFFFFFF),
                                                ),
                                              ),
                                              const SizedBox(height: 26),
                                              SizedBox(
                                                height: 60,
                                                child: FilledButton.icon(
                                                  style: FilledButton.styleFrom(
                                                    backgroundColor: _accent,
                                                    foregroundColor: Colors.white,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(16),
                                                    ),
                                                  ),
                                                  icon: const Icon(Icons.route),
                                                  label: Text(
                                                    AppLanguage.t('plan_journey'),
                                                  ),
                                                  onPressed: () {
                                                    if (!ElminaMapConfig.routesReady) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(content: Text(AppLanguage.t('journey_resumes_msg'))),
                                                      );
                                                      return;
                                                    }
                                                    Navigator.push(context, MaterialPageRoute(
                                                      builder: (_) => const RecommendedJourneyPage(),
                                                    ));
                                                  },
                                                ),
                                              ),
                                              const SizedBox(height: 14),
                                              SizedBox(
                                                height: 60,
                                                child: FilledButton.icon(
                                                  style: _glassButtonStyle(),
                                                  icon: const Icon(Icons.map_outlined),
                                                  label: Text(
                                                    AppLanguage.t('explore_map'),
                                                  ),
                                                  onPressed: () => Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) =>
                                                          const MapExplorerPage(),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const Positioned(
                    top: 14,
                    right: 18,
                    child: LanguageSwitchCapsule(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static ButtonStyle _glassButtonStyle() {
    return FilledButton.styleFrom(
      backgroundColor: const Color(0x38FFFFFF),
      foregroundColor: Colors.white,
      side: const BorderSide(color: Color(0x66FFFFFF)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}
