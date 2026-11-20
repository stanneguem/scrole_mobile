import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _ink = Color(0xFF090A0F);
const _panel = Color(0xFF12141D);
const _purple = Color(0xFF8B5CF6);
const _pink = Color(0xFFEC4899);
const _muted = Color(0xFFA4A7B5);
const _white = Color(0xFFF8F7FC);

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();
  final _featuresKey = GlobalKey();
  final _communitiesKey = GlobalKey();
  final _eventsKey = GlobalKey();
  final _downloadKey = GlobalKey();
  late final AnimationController _introController;
  late final Animation<double> _introAnimation;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..forward();
    _introAnimation = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _introController.dispose();
    super.dispose();
  }

  void _goTo(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeInOutCubic,
      alignment: 0.08,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ink,
      body: Stack(
        children: [
          const Positioned(
            top: -210,
            left: -180,
            child: _Glow(color: Color(0x338B5CF6), size: 620),
          ),
          const Positioned(
            top: 520,
            right: -260,
            child: _Glow(color: Color(0x1FEC4899), size: 620),
          ),
          FadeTransition(
            opacity: _introAnimation,
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                children: [
                  _NavigationBar(
                    onFeatures: () => _goTo(_featuresKey),
                    onCommunities: () => _goTo(_communitiesKey),
                    onEvents: () => _goTo(_eventsKey),
                    onDownload: () => _goTo(_downloadKey),
                  ),
                  _HeroSection(onExplore: () => _goTo(_featuresKey)),
                  _MobileAvailabilityBanner(
                    onLearnMore: () => _goTo(_downloadKey),
                  ),
                  _Section(
                    key: _featuresKey,
                    eyebrow: 'TON UNIVERS, TON FIL',
                    title: 'Tout ce qui te passionne,\nau même endroit.',
                    subtitle:
                        'Partage tes moments, découvre de nouveaux contenus et garde le lien avec les personnes qui comptent.',
                    child: const _FeatureGrid(),
                  ),
                  _CommunitySection(key: _communitiesKey),
                  _EventSection(key: _eventsKey),
                  _DownloadSection(key: _downloadKey),
                  const _Footer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationBar extends StatelessWidget {
  const _NavigationBar({
    required this.onFeatures,
    required this.onCommunities,
    required this.onEvents,
    required this.onDownload,
  });

  final VoidCallback onFeatures;
  final VoidCallback onCommunities;
  final VoidCallback onEvents;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 22 : 56,
            vertical: 20,
          ),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0x18FFFFFF))),
          ),
          child: Row(
            children: [
              const _Brand(),
              const Spacer(),
              if (!compact) ...[
                _NavText(label: 'Découvrir', onTap: onFeatures),
                const SizedBox(width: 30),
                _NavText(label: 'Communautés', onTap: onCommunities),
                const SizedBox(width: 30),
                _NavText(label: 'Événements', onTap: onEvents),
                const SizedBox(width: 34),
              ],
              _GradientButton(
                label: compact ? 'Découvrir' : 'Découvrir Scrole',
                icon: Icons.arrow_forward_rounded,
                onTap: onDownload,
                compact: compact,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_purple, _pink],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _purple.withOpacity(.28),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(
            Icons.bolt_rounded,
            color: Colors.white,
            size: 27,
          ),
        ),
        const SizedBox(width: 11),
        Text(
          'Scrole',
          style: GoogleFonts.spaceGrotesk(
            color: _white,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -.8,
          ),
        ),
      ],
    );
  }
}

class _NavText extends StatelessWidget {
  const _NavText({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: _muted,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 12),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      );
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.onExplore});
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final horizontal = constraints.maxWidth < 650 ? 24.0 : 64.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(horizontal, 76, horizontal, 88),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Expanded(flex: 11, child: _HeroCopy()),
                        const SizedBox(width: 36),
                        Expanded(
                          flex: 9,
                          child: _ProductPreview(),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        const _HeroCopy(centered: true),
                        const SizedBox(height: 54),
                        _ProductPreview(compact: true),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({this.centered = false});
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final align =
        centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: align,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0x1C8B5CF6),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: const Color(0x558B5CF6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome, color: Color(0xFFC4A7FF), size: 15),
              const SizedBox(width: 8),
              Text(
                'LE RÉSEAU SOCIAL QUI RASSEMBLE',
                style: GoogleFonts.inter(
                  color: const Color(0xFFD2C1FF),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        RichText(
          textAlign: centered ? TextAlign.center : TextAlign.left,
          text: TextSpan(
            style: GoogleFonts.spaceGrotesk(
              color: _white,
              fontSize: centered ? 48 : 58,
              height: 1.06,
              fontWeight: FontWeight.w800,
              letterSpacing: -2.3,
            ),
            children: const [
              TextSpan(text: 'Vis tes passions.\n'),
              TextSpan(
                text: 'Partage tes\n',
                style: TextStyle(color: Color(0xFFB99BFF)),
              ),
              TextSpan(text: 'moments.'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 530),
          child: Text(
            'Avec Scrole, retrouve tes amis, partage ce que tu vis, échange dans des communautés et découvre les événements qui te ressemblent.',
            textAlign: centered ? TextAlign.center : TextAlign.left,
            style: GoogleFonts.inter(
              color: _muted,
              fontSize: 16,
              height: 1.8,
            ),
          ),
        ),
        const SizedBox(height: 34),
        Wrap(
          alignment: centered ? WrapAlignment.center : WrapAlignment.start,
          spacing: 12,
          runSpacing: 12,
          children: [
            _GradientButton(
              label: 'Explorer Scrole',
              icon: Icons.arrow_downward_rounded,
              onTap: () => Scrollable.ensureVisible(
                context,
                duration: const Duration(milliseconds: 500),
              ),
            ),
            const _OutlinePill(
              icon: Icons.phone_iphone_rounded,
              label: 'Pensé pour le mobile',
            ),
          ],
        ),
        const SizedBox(height: 36),
        Wrap(
          alignment: centered ? WrapAlignment.center : WrapAlignment.start,
          spacing: 22,
          runSpacing: 12,
          children: const [
            _CheckLine(label: 'Un fil qui te ressemble'),
            _CheckLine(label: 'Des communautés vivantes'),
            _CheckLine(label: 'Des événements à découvrir'),
          ],
        ),
      ],
    );
  }
}

class _ProductPreview extends StatelessWidget {
  const _ProductPreview({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: compact ? 560 : 590),
        child: AspectRatio(
          aspectRatio: compact ? 1.15 : 1.08,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 330,
                height: 330,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _purple.withOpacity(.28),
                      _pink.withOpacity(.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              Positioned(
                left: compact ? 0 : 8,
                top: compact ? 18 : 30,
                child: const _FloatingTag(
                  icon: Icons.favorite_rounded,
                  text: 'Partager un moment',
                  color: _pink,
                ),
              ),
              Positioned(
                right: compact ? 0 : 4,
                bottom: compact ? 22 : 42,
                child: const _FloatingTag(
                  icon: Icons.event_rounded,
                  text: 'Trouver un événement',
                  color: Color(0xFF9B8CFF),
                ),
              ),
              Transform.rotate(
                angle: -.055,
                child: const _FeedPhoneMockup(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedPhoneMockup extends StatelessWidget {
  const _FeedPhoneMockup();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 238,
      height: 440,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xFF252735),
        borderRadius: BorderRadius.circular(37),
        border: Border.all(color: const Color(0xFF77718D), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: _purple.withOpacity(.22),
            blurRadius: 70,
            offset: const Offset(0, 24),
          ),
          const BoxShadow(
            color: Colors.black54,
            blurRadius: 35,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(29),
        child: Container(
          color: _ink,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 58,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF3D4050),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Row(
                  children: [
                    const _MiniBrand(),
                    const SizedBox(width: 7),
                    Text(
                      'Scrole',
                      style: GoogleFonts.spaceGrotesk(
                        color: _white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.search, color: _muted, size: 19),
                    const SizedBox(width: 10),
                    const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: _muted,
                      size: 18,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0x1FFFFFFF)),
              SizedBox(
                height: 82,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  scrollDirection: Axis.horizontal,
                  children: const [
                    _StoryBubble(label: 'Votre story', own: true),
                    _StoryBubble(label: 'Maya'),
                    _StoryBubble(label: 'Kevin'),
                    _StoryBubble(label: 'Ariane'),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: _MockPost(),
              ),
              const Spacer(),
              Container(
                height: 43,
                decoration: const BoxDecoration(
                  color: Color(0xFF12141D),
                  border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Icon(Icons.home_rounded, color: Color(0xFFB99BFF), size: 19),
                    Icon(Icons.groups_rounded, color: _muted, size: 19),
                    Icon(Icons.add_circle_outline, color: _muted, size: 19),
                    Icon(Icons.event_outlined, color: _muted, size: 19),
                    Icon(Icons.person_outline, color: _muted, size: 19),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniBrand extends StatelessWidget {
  const _MiniBrand();

  @override
  Widget build(BuildContext context) => Container(
        width: 25,
        height: 25,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_purple, _pink]),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 17),
      );
}

class _StoryBubble extends StatelessWidget {
  const _StoryBubble({required this.label, this.own = false});
  final String label;
  final bool own;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: own
                    ? const [Color(0xFF454858), Color(0xFF454858)]
                    : const [_purple, _pink, Color(0xFFFFB86B)],
              ),
            ),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFF272A38),
              child: own
                  ? const Icon(Icons.add, color: _white, size: 20)
                  : Text(
                      label.characters.first,
                      style: GoogleFonts.spaceGrotesk(
                        color: _white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class _MockPost extends StatelessWidget {
  const _MockPost();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0x16FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: Color(0xFF7755A8),
                  child: Icon(Icons.person, size: 15, color: Colors.white),
                ),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Communauté créative',
                    style: TextStyle(
                      color: _white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(Icons.more_horiz, color: _muted, size: 17),
              ],
            ),
          ),
          Container(
            height: 150,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF4C347A),
                  Color(0xFF9C4D83),
                  Color(0xFFE58B70),
                ],
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.auto_awesome_rounded,
                color: Color(0xFFFFE5D9),
                size: 54,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 9, 10, 10),
            child: Row(
              children: [
                Icon(Icons.favorite_border, color: _white, size: 16),
                SizedBox(width: 12),
                Icon(Icons.mode_comment_outlined, color: _white, size: 16),
                SizedBox(width: 12),
                Icon(Icons.repeat_rounded, color: _white, size: 16),
                Spacer(),
                Icon(Icons.bookmark_border, color: _white, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingTag extends StatelessWidget {
  const _FloatingTag({
    required this.icon,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xF21A1B27),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(.12)),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 22, offset: Offset(0, 8)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 17),
            const SizedBox(width: 8),
            Text(
              text,
              style: GoogleFonts.inter(
                color: _white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

class _MobileAvailabilityBanner extends StatelessWidget {
  const _MobileAvailabilityBanner({required this.onLearnMore});
  final VoidCallback onLearnMore;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(22),
      constraints: const BoxConstraints(maxWidth: 1100),
      decoration: BoxDecoration(
        color: const Color(0xFF171522),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x558B5CF6)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final copy = const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Scrole sur ordinateur',
                style: TextStyle(
                  color: _white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'La version tablette et ordinateur arrive progressivement. En attendant, retrouve toute l’expérience Scrole sur ton téléphone.',
                style: TextStyle(color: _muted, fontSize: 12, height: 1.6),
              ),
            ],
          );
          return compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    copy,
                    const SizedBox(height: 14),
                    _TextAction(label: 'En savoir plus', onTap: onLearnMore),
                  ],
                )
              : Row(
                  children: [
                    const Icon(
                      Icons.phone_android_rounded,
                      color: Color(0xFFC4A7FF),
                      size: 30,
                    ),
                    const SizedBox(width: 18),
                    const Expanded(child: _AvailabilityCopy()),
                    const SizedBox(width: 14),
                    _TextAction(label: 'En savoir plus', onTap: onLearnMore),
                  ],
                );
        },
      ),
    );
  }
}

class _AvailabilityCopy extends StatelessWidget {
  const _AvailabilityCopy();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Scrole sur ordinateur',
            style: TextStyle(
              color: _white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'La version tablette et ordinateur arrive progressivement. En attendant, retrouve toute l’expérience Scrole sur ton téléphone.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.6),
          ),
        ],
      );
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFC4A7FF),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 112, 24, 50),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: Column(
            children: [
              _Eyebrow(eyebrow),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                  color: _white,
                  fontSize: 40,
                  height: 1.12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.4,
                ),
              ),
              const SizedBox(height: 17),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 650),
                child: Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: _muted,
                    fontSize: 14,
                    height: 1.8,
                  ),
                ),
              ),
              const SizedBox(height: 48),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid();

  @override
  Widget build(BuildContext context) {
    const items = [
      _FeatureData(
        Icons.dynamic_feed_rounded,
        'Un fil à ton image',
        'Publications, photos et vidéos pour raconter ce que tu vis et découvrir les moments partagés par les autres.',
        Color(0xFF9B8CFF),
      ),
      _FeatureData(
        Icons.camera_alt_rounded,
        'Des stories spontanées',
        'Partage les instants du quotidien et retrouve les stories des personnes que tu suis.',
        Color(0xFFFF8BB5),
      ),
      _FeatureData(
        Icons.groups_rounded,
        'Des communautés',
        'Rejoins des espaces de discussion autour de tes centres d’intérêt et échange avec des passionnés.',
        Color(0xFF69D6C2),
      ),
      _FeatureData(
        Icons.movie_filter_rounded,
        'Des réels à découvrir',
        'Explore des vidéos courtes, découvre de nouvelles idées et partage ta créativité.',
        Color(0xFFFFB86B),
      ),
      _FeatureData(
        Icons.chat_bubble_rounded,
        'Des échanges directs',
        'Discute en privé ou dans les conversations de tes communautés.',
        Color(0xFF82B7FF),
      ),
      _FeatureData(
        Icons.event_available_rounded,
        'Des événements',
        'Découvre les rendez-vous à venir, consulte leurs activités et garde les événements qui t’intéressent.',
        Color(0xFFC69BFF),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 560
                ? 2
                : 1;
        final ratio = columns == 3 ? 1.42 : columns == 2 ? 1.55 : 2.25;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: ratio,
          ),
          itemBuilder: (context, index) => _FeatureCard(data: items[index]),
        );
      },
    );
  }
}

class _FeatureData {
  const _FeatureData(this.icon, this.title, this.description, this.color);
  final IconData icon;
  final String title;
  final String description;
  final Color color;
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.data});
  final _FeatureData data;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: data.color.withOpacity(.13),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(data.icon, color: data.color, size: 24),
            ),
            const SizedBox(height: 19),
            Text(
              data.title,
              style: GoogleFonts.spaceGrotesk(
                color: _white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 9),
            Expanded(
              child: Text(
                data.description,
                style: GoogleFonts.inter(
                  color: _muted,
                  fontSize: 12,
                  height: 1.7,
                ),
              ),
            ),
          ],
        ),
      );
}

class _CommunitySection extends StatelessWidget {
  const _CommunitySection({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 70),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 90),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF171326), Color(0xFF11121B)],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 820;
              final copy = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Eyebrow('ENSEMBLE, C’EST MIEUX'),
                  const SizedBox(height: 20),
                  Text(
                    'Trouve ta\ncommunauté.',
                    style: GoogleFonts.spaceGrotesk(
                      color: _white,
                      fontSize: 44,
                      height: 1.08,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Musique, culture, sport, jeux, passions créatives… Rejoins des personnes qui partagent tes centres d’intérêt et faites vivre vos discussions.',
                    style: GoogleFonts.inter(
                      color: _muted,
                      fontSize: 14,
                      height: 1.8,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _CheckLine(label: 'Des espaces publics ou privés'),
                  const SizedBox(height: 12),
                  const _CheckLine(label: 'Des publications et conversations'),
                  const SizedBox(height: 12),
                  const _CheckLine(label: 'Des rencontres autour de tes passions'),
                ],
              );
              const visual = _CommunityVisual();
              return wide
                  ? Row(
                      children: [
                        Expanded(child: copy),
                        const SizedBox(width: 70),
                        const Expanded(child: visual),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        copy,
                        const SizedBox(height: 44),
                        const visual,
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }
}

class _CommunityVisual extends StatelessWidget {
  const _CommunityVisual();

  @override
  Widget build(BuildContext context) {
    const entries = [
      (Icons.music_note_rounded, 'Musique & concerts', 'Partager les découvertes', Color(0xFFB18CFF)),
      (Icons.sports_esports_rounded, 'Gaming & pop culture', 'Jouer, échanger, se retrouver', Color(0xFF72C7FF)),
      (Icons.palette_rounded, 'Art & créativité', 'Montrer ce que tu imagines', Color(0xFFFF9EBC)),
    ];
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0F17),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(.09)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 40, offset: Offset(0, 18)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.groups_rounded, color: Color(0xFFC4A7FF), size: 20),
              SizedBox(width: 9),
              Text(
                'À explorer',
                style: TextStyle(color: _white, fontSize: 15, fontWeight: FontWeight.w800),
              ),
              Spacer(),
              Icon(Icons.more_horiz, color: _muted),
            ],
          ),
          const SizedBox(height: 18),
          for (final entry in entries) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _panel,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(.06)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: entry.$4.withOpacity(.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(entry.$1, color: entry.$4, size: 24),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.$2, style: const TextStyle(color: _white, fontSize: 13, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(entry.$3, style: const TextStyle(color: _muted, fontSize: 11)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, color: _muted, size: 13),
                ],
              ),
            ),
            const SizedBox(height: 11),
          ],
        ],
      ),
    );
  }
}

class _EventSection extends StatelessWidget {
  const _EventSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 110, 24, 90),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 820;
              final visual = const _EventVisual();
              final copy = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Eyebrow('SORS, DÉCOUVRE, PARTICIPE'),
                  const SizedBox(height: 20),
                  Text(
                    'La prochaine\nexpérience commence ici.',
                    style: GoogleFonts.spaceGrotesk(
                      color: _white,
                      fontSize: 42,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Repère les événements qui t’intéressent, découvre leurs informations et leurs activités, puis retrouve les personnes qui y seront.',
                    style: GoogleFonts.inter(
                      color: _muted,
                      fontSize: 14,
                      height: 1.8,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _CheckLine(label: 'Découverte des événements'),
                  const SizedBox(height: 12),
                  const _CheckLine(label: 'Informations et activités'),
                  const SizedBox(height: 12),
                  const _CheckLine(label: 'Billetterie et contrôle par QR code selon l’événement'),
                ],
              );
              return wide
                  ? Row(
                      children: [
                        Expanded(child: visual),
                        const SizedBox(width: 76),
                        Expanded(child: copy),
                      ],
                    )
                  : Column(
                      children: [
                        visual,
                        const SizedBox(height: 48),
                        copy,
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }
}

class _EventVisual extends StatelessWidget {
  const _EventVisual();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 490),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 190,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF37265C), Color(0xFF9A4C85), Color(0xFFE69B6B)],
              ),
            ),
            child: Stack(
              children: [
                const Positioned(
                  top: 18,
                  left: 18,
                  child: _TinyTag(label: 'À DÉCOUVRIR'),
                ),
                Positioned(
                  bottom: 18,
                  left: 18,
                  right: 18,
                  child: Text(
                    'Tes passions\nprennent vie.',
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 27,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Positioned(
                  top: 42,
                  right: 24,
                  child: Icon(Icons.auto_awesome, color: Color(0xFFFFD9C2), size: 54),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.calendar_month_rounded, color: Color(0xFFC4A7FF), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Découvre les rendez-vous près de toi', style: TextStyle(color: _white, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0x228B5CF6),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Text('Explorer', style: TextStyle(color: Color(0xFFD2C1FF), fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 9),
          const Text(
            'Concerts • Culture • Gaming • Rencontres',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _DownloadSection extends StatelessWidget {
  const _DownloadSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 100),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 58),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF34245A), Color(0xFF1C1930), Color(0xFF171522)],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0x558B5CF6)),
              boxShadow: [
                BoxShadow(color: _purple.withOpacity(.12), blurRadius: 50, offset: const Offset(0, 15)),
              ],
            ),
            child: Column(
              children: [
                const Icon(Icons.bolt_rounded, color: Color(0xFFE0D2FF), size: 34),
                const SizedBox(height: 18),
                Text(
                  'Et si on vivait plus de choses ensemble ?',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    color: _white,
                    fontSize: 34,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Text(
                    'Rejoins Scrole sur mobile pour partager tes moments, retrouver tes communautés et découvrir les événements qui t’inspirent.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(color: const Color(0xFFD0C9DF), fontSize: 14, height: 1.8),
                  ),
                ),
                const SizedBox(height: 25),
                const _OutlinePill(
                  icon: Icons.phone_iphone_rounded,
                  label: 'L’expérience Scrole est actuellement disponible sur mobile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x18FFFFFF))),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 650;
              final brand = const _Brand();
              const legal = Text(
                '© Scrole · Tous droits réservés',
                style: TextStyle(color: Color(0xFF777987), fontSize: 11),
              );
              return compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        brand,
                        const SizedBox(height: 18),
                        legal,
                        const SizedBox(height: 8),
                        const Text(
                          'Le réseau social de tes passions et de tes événements.',
                          style: TextStyle(color: Color(0xFF777987), fontSize: 11),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        brand,
                        const Spacer(),
                        const Text(
                          'Le réseau social de tes passions et de tes événements.',
                          style: TextStyle(color: Color(0xFF777987), fontSize: 11),
                        ),
                        const Spacer(),
                        legal,
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.compact = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_purple, _pink]),
          borderRadius: BorderRadius.circular(13),
          boxShadow: [
            BoxShadow(color: _purple.withOpacity(.22), blurRadius: 22, offset: const Offset(0, 7)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(13),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 15 : 20,
                vertical: 13,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(icon, color: Colors.white, size: 16),
                ],
              ),
            ),
          ),
        ),
      );
}

class _OutlinePill extends StatelessWidget {
  const _OutlinePill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.035),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withOpacity(.13)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFFC4A7FF), size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: GoogleFonts.inter(color: _white, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}

class _CheckLine extends StatelessWidget {
  const _CheckLine({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFFB99BFF), size: 17),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFFC5C4CE), fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      );
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: GoogleFonts.inter(
          color: const Color(0xFFC4A7FF),
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.8,
        ),
      );
}

class _TinyTag extends StatelessWidget {
  const _TinyTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.25),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withOpacity(.35)),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1),
        ),
      );
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, Colors.transparent]),
          ),
        ),
      );
}
