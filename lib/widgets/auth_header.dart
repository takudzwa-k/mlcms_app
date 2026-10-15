import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// The teal banner at the top of the Login and Sign up screens.
class AuthHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? tagline;
  final bool showBack;

  const AuthHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.tagline,
    this.showBack = false,
  });

  Widget _circle(double size, int alpha) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withAlpha(alpha),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // light status-bar icons, because the banner is dark
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B8379), Color(0xFF065D56)],
          ),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(top: -70, right: -50, child: _circle(230, 22)),
            Positioned(top: 46, right: 74, child: _circle(54, 16)),
            Positioned(bottom: -90, left: -60, child: _circle(180, 14)),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showBack)
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => Navigator.maybePop(context),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.arrow_back, size: 18, color: Colors.white),
                              SizedBox(width: 6),
                              Text(
                                'Back',
                                style: TextStyle(color: Colors.white, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 12),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(17),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(40),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/images/logo_fridge.png',
                            errorBuilder: (context, error, stack) => const Icon(
                              Icons.kitchen_rounded,
                              color: AppColors.teal,
                              size: 30,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  color: Colors.white.withAlpha(205),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (tagline != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        tagline!,
                        style: TextStyle(
                          color: Colors.white.withAlpha(205),
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The pink error box (or green confirmation box) used on the auth screens.
class AuthMessage extends StatelessWidget {
  final String text;
  final bool isError;

  const AuthMessage({super.key, required this.text, this.isError = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isError ? AppColors.dangerLight : AppColors.okLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isError ? AppColors.danger : AppColors.ok,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          height: 1.35,
        ),
      ),
    );
  }
}