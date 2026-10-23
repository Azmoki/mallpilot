import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLang { en, bm, zh }

class AppLanguage {
  static const String _prefKey = 'mallpilot_app_language';
  static final ValueNotifier<AppLang> current = ValueNotifier<AppLang>(AppLang.en);

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved == 'bm') {
        current.value = AppLang.bm;
      } else if (saved == 'zh') {
        current.value = AppLang.zh;
      } else {
        current.value = AppLang.en;
      }
    } catch (_) {}
  }

  static void setLanguage(AppLang lang) {
    if (current.value == lang) return;
    current.value = lang;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_prefKey, lang.name);
    }).catchError((_) {});
  }

  static String t(String key) {
    final lang = current.value;
    final map = _translations[key];
    if (map == null) return key;
    return map[lang] ?? map[AppLang.en] ?? key;
  }

  static String subCategory(String key) {
    final lang = current.value;
    final map = _subCategoryTranslations[key];
    if (map == null) return key;
    return map[lang] ?? map[AppLang.en] ?? key;
  }

  static String facilityName(String name) {
    final lang = current.value;
    final map = _facilityNameTranslations[name];
    if (map == null) return name;
    return map[lang] ?? map[AppLang.en] ?? name;
  }

  static String facilityDescription(String desc) {
    final lang = current.value;
    final map = _facilityDescTranslations[desc];
    if (map == null) return desc;
    return map[lang] ?? map[AppLang.en] ?? desc;
  }

  static String category(String name) {
    final lang = current.value;
    final map = _categoryTranslations[name];
    if (map != null) return map[lang] ?? map[AppLang.en] ?? name;
    final subMap = _subCategoryTranslations[name];
    if (subMap != null) return subMap[lang] ?? subMap[AppLang.en] ?? name;
    return name;
  }

  static String stopProgress(int curr, int total) {
    final lang = current.value;
    if (lang == AppLang.zh) return '第 $curr 站（共 $total 站）';
    if (lang == AppLang.bm) return 'Hentian $curr drpd $total';
    return 'Stop $curr of $total';
  }

  static const Map<String, Map<AppLang, String>> _translations = {
    // Home Page
    'slogan': {
      AppLang.en: 'Less searching. More discovering.',
      AppLang.bm: 'Kurang mencari. Lebih meneroka.',
      AppLang.zh: '少一点寻觅，多一点探索。',
    },
    'sub_tag': {
      AppLang.en: 'Elmina Lakeside Mall · Demo',
      AppLang.bm: 'Elmina Lakeside Mall · Demo',
      AppLang.zh: 'Elmina Lakeside Mall · 演示版',
    },
    'plan_journey': {
      AppLang.en: 'Plan My Journey',
      AppLang.bm: 'Rancang Perjalanan',
      AppLang.zh: '规划我的行程',
    },
    'explore_map': {
      AppLang.en: 'Explore Map & Stores',
      AppLang.bm: 'Teroka Peta & Kedai',
      AppLang.zh: '探索地图与店铺',
    },
    'journey_resumes_msg': {
      AppLang.en: 'Journey planning resumes after Elmina pedestrian graph and shop mappings are ready.',
      AppLang.bm: 'Perancangan perjalanan akan bermula selepas graf pejalan kaki siap.',
      AppLang.zh: '行程规划将在步行路线与店铺数据就绪后开启。',
    },

    // Steps
    'step_interests': {
      AppLang.en: 'Interests',
      AppLang.bm: 'Minat',
      AppLang.zh: '兴趣选择',
    },
    'step_preferences': {
      AppLang.en: 'Preferences',
      AppLang.bm: 'Pilihan',
      AppLang.zh: '偏好设置',
    },
    'step_journey': {
      AppLang.en: 'Your Journey',
      AppLang.bm: 'Perjalanan',
      AppLang.zh: '推荐路线',
    },

    // Interest categories
    'cat_food': {
      AppLang.en: 'Food & Drinks',
      AppLang.bm: 'Makanan & Minuman',
      AppLang.zh: '餐饮美食',
    },
    'cat_fashion': {
      AppLang.en: 'Fashion',
      AppLang.bm: 'Fesyen',
      AppLang.zh: '时尚服饰',
    },
    'cat_beauty': {
      AppLang.en: 'Beauty & Care',
      AppLang.bm: 'Kecantikan & Penjagaan',
      AppLang.zh: '美容护理',
    },
    'cat_electronics': {
      AppLang.en: 'Electronics',
      AppLang.bm: 'Elektronik',
      AppLang.zh: '数码家电',
    },
    'cat_sportswear': {
      AppLang.en: 'Sports',
      AppLang.bm: 'Sukan',
      AppLang.zh: '运动户外',
    },
    'cat_home': {
      AppLang.en: 'Home & Lifestyle',
      AppLang.bm: 'Gaya Hidup & Rumah',
      AppLang.zh: '家居生活',
    },
    'cat_groceries': {
      AppLang.en: 'Groceries',
      AppLang.bm: 'Barangan Runcit',
      AppLang.zh: '超市生鲜',
    },
    'cat_accessories': {
      AppLang.en: 'Accessories',
      AppLang.bm: 'Aksesori',
      AppLang.zh: '钟表饰品',
    },
    'cat_entertainment': {
      AppLang.en: 'Entertainment',
      AppLang.bm: 'Hiburan',
      AppLang.zh: '休闲娱乐',
    },

    // Step 0: Interests
    'what_interested_in': {
      AppLang.en: 'What are you interested in?',
      AppLang.bm: 'Apa yang anda minati?',
      AppLang.zh: '您对什么感兴趣？',
    },
    'choose_interests_desc': {
      AppLang.en: 'Choose one or more interests. We will find shops that match your choices while balancing variety across categories.',
      AppLang.bm: 'Pilih satu atau lebih minat. Kami akan cadangkan kedai mengikut pilihan anda.',
      AppLang.zh: '选择一个或多个兴趣，我们将为你挑选最匹配的店铺。',
    },
    'where_starting': {
      AppLang.en: 'Where are you starting?',
      AppLang.bm: 'Dari mana anda bermula?',
      AppLang.zh: '您从哪里出发？',
    },
    'pin_start_btn': {
      AppLang.en: 'Pin My Start on Map',
      AppLang.bm: 'Pilih Titik Mula di Peta',
      AppLang.zh: '在地图上标记起点',
    },
    'change_pin_start_btn': {
      AppLang.en: 'Change Pin My Start',
      AppLang.bm: 'Tukar Titik Mula',
      AppLang.zh: '修改起点位置',
    },
    'start_pinned_desc': {
      AppLang.en: 'Start point pinned to the indoor walking network',
      AppLang.bm: 'Titik mula ditetapkan pada laluan pejalan kaki',
      AppLang.zh: '起点已标记在商场步行路线上',
    },
    'pin_start_hint': {
      AppLang.en: 'Pin your start to personalize the walking route.',
      AppLang.bm: 'Tetapkan titik mula untuk menyesuaikan laluan.',
      AppLang.zh: '标记您的起点以个性化规划步行路线。',
    },
    'btn_next_preferences': {
      AppLang.en: 'Next: Spending & Journey Style',
      AppLang.bm: 'Seterusnya: Bajet & Gaya',
      AppLang.zh: '下一步：消费偏好与风格',
    },

    // Step 1: Preferences
    'personalize_journey': {
      AppLang.en: 'Personalize your journey',
      AppLang.bm: 'Peribadikan perjalanan anda',
      AppLang.zh: '个性化您的行程',
    },
    'personalize_desc': {
      AppLang.en: 'Choose how you would like to shop. The suggestions will balance your selected interests with walking efficiency.',
      AppLang.bm: 'Pilih gaya membeli-belah anda mengikut bajet dan masa.',
      AppLang.zh: '选择您的购物方式，系统将平衡兴趣偏好与步行效率。',
    },
    'spending_pref': {
      AppLang.en: 'Spending preference',
      AppLang.bm: 'Pilihan perbelanjaan',
      AppLang.zh: '消费水平偏好',
    },
    'spending_affordable': {
      AppLang.en: 'Affordable',
      AppLang.bm: 'Mampu Milik',
      AppLang.zh: '平价实惠',
    },
    'spending_affordable_desc': {
      AppLang.en: 'Favor lower-priced shops within their category',
      AppLang.bm: 'Lebih memilih kedai dengan harga berpatutan',
      AppLang.zh: '优先推荐该类别下性价比高的店铺',
    },
    'spending_balanced': {
      AppLang.en: 'Balanced',
      AppLang.bm: 'Seimbang',
      AppLang.zh: '适中均衡',
    },
    'spending_balanced_desc': {
      AppLang.en: 'Mix of price levels',
      AppLang.bm: 'Campuran pelbagai tahap harga',
      AppLang.zh: '涵盖不同价位的综合搭配',
    },
    'spending_premium': {
      AppLang.en: 'Premium',
      AppLang.bm: 'Premium',
      AppLang.zh: '品质优享',
    },
    'spending_premium_desc': {
      AppLang.en: 'Favor higher-priced options',
      AppLang.bm: 'Lebih memilih pilihan mewah dan premium',
      AppLang.zh: '优先推荐高端及品质店铺',
    },
    'journey_experience': {
      AppLang.en: 'Journey experience',
      AppLang.bm: 'Gaya perjalanan',
      AppLang.zh: '行程游览风格',
    },
    'style_quick': {
      AppLang.en: 'Quick Shopping',
      AppLang.bm: 'Membeli-belah Pantas',
      AppLang.zh: '高效速达',
    },
    'style_quick_desc': {
      AppLang.en: 'Start with 3 shops, minimal detours',
      AppLang.bm: 'Mula dengan 3 kedai, laluan paling singkat',
      AppLang.zh: '精选 3 家店铺，路线最短不绕路',
    },
    'style_balanced': {
      AppLang.en: 'Balanced Journey',
      AppLang.bm: 'Perjalanan Seimbang',
      AppLang.zh: '舒适漫步',
    },
    'style_balanced_desc': {
      AppLang.en: 'Start with 4 shops across interests',
      AppLang.bm: 'Mula dengan 4 kedai pelbagai minat',
      AppLang.zh: '推荐 4 家店铺，品类均衡丰富',
    },
    'style_discovery': {
      AppLang.en: 'Discovery Journey',
      AppLang.bm: 'Perjalanan Penerokaan',
      AppLang.zh: '深度探店',
    },
    'style_discovery_desc': {
      AppLang.en: 'Start with 5 shops and more variety',
      AppLang.bm: 'Mula dengan 5 kedai dengan lebih variasi',
      AppLang.zh: '探索 5 家店铺，享受更多惊喜',
    },
    'btn_show_recommendations': {
      AppLang.en: 'Show My Recommended Journey',
      AppLang.bm: 'Tunjukkan Cadangan Perjalanan',
      AppLang.zh: '生成我的推荐行程',
    },
    'btn_back_to_interests': {
      AppLang.en: 'Back to Interests',
      AppLang.bm: 'Kembali ke Minat',
      AppLang.zh: '返回修改兴趣',
    },

    // Step 2: Results
    'your_recommended_journey': {
      AppLang.en: 'Your Recommended Journey',
      AppLang.bm: 'Cadangan Perjalanan Anda',
      AppLang.zh: '为您量身推荐的行程',
    },
    'category_composition': {
      AppLang.en: 'Suggested category composition',
      AppLang.bm: 'Komposisi kategori dicadangkan',
      AppLang.zh: '建议游览品类构成',
    },
    'keep_lock_hint': {
      AppLang.en: 'Keep, remove or lock shops before generating your path.',
      AppLang.bm: 'Simpan, padam atau kunci kedai sebelum menjana laluan.',
      AppLang.zh: '在生成路径前，您可以增删或锁定心仪店铺。',
    },
    'btn_shuffle': {
      AppLang.en: 'Shuffle Recommendations',
      AppLang.bm: 'Rawak Cadangan',
      AppLang.zh: '换一批推荐',
    },
    'btn_generate_path': {
      AppLang.en: 'Generate Path',
      AppLang.bm: 'Jana Laluan',
      AppLang.zh: '生成导航路线',
    },
    'btn_edit_spending': {
      AppLang.en: 'Edit Spending & Journey Style',
      AppLang.bm: 'Ubah Bajet & Gaya',
      AppLang.zh: '修改消费偏好与风格',
    },
    'btn_change_interests': {
      AppLang.en: 'Change Interests or Start Point',
      AppLang.bm: 'Ubah Minat atau Titik Mula',
      AppLang.zh: '重新选择兴趣或起点',
    },
    'shops_count_suffix': {
      AppLang.en: 'shops',
      AppLang.bm: 'kedai',
      AppLang.zh: '家店铺',
    },

    // Pin location page
    'pin_location_title': {
      AppLang.en: 'Pin your current location',
      AppLang.bm: 'Tetapkan lokasi semasa anda',
      AppLang.zh: '标记您的当前位置',
    },
    'pin_location_intro': {
      AppLang.en: 'Pin where you are on the Ground Floor map. Pinch to zoom and tap a walkway. The marker snaps to the nearest mapped corridor. This is a manual location, not live GPS.',
      AppLang.bm: 'Pilih lokasi anda pada peta Aras Bawah (GF). Cubit untuk zum dan ketik pada laluan pejalan kaki.',
      AppLang.zh: '请在地面层（GF）地图上标记您所在的位置。双指缩放并轻触走道，标记将自动吸附至最近的步行通道。',
    },
    'pin_start_success': {
      AppLang.en: 'Starting point set on walkway.',
      AppLang.bm: 'Titik mula berjaya ditetapkan di laluan.',
      AppLang.zh: '已在步行通道上设定起点。',
    },
    'use_this_start': {
      AppLang.en: 'Use this starting point',
      AppLang.bm: 'Gunakan titik mula ini',
      AppLang.zh: '使用此位置作为起点',
    },
    'point_too_far_err': {
      AppLang.en: 'Selected point is too far from a mapped corridor. Tap closer to the walkway.',
      AppLang.bm: 'Titik yang dipilih terlalu jauh dari laluan. Sila ketik berhampiran laluan.',
      AppLang.zh: '所选位置距离走道过远，请点击走道附近区域。',
    },

    // Navigation page
    'indoor_nav_title': {
      AppLang.en: 'Indoor Navigation',
      AppLang.bm: 'Navigasi Dalam Bangunan',
      AppLang.zh: '商场室内导航',
    },
    'calc_route_msg': {
      AppLang.en: 'Calculating route using MallPilot...',
      AppLang.bm: 'Mengira laluan menggunakan MallPilot...',
      AppLang.zh: '正在通过 MallPilot 计算最佳路线...',
    },
    'start_navigation': {
      AppLang.en: 'Start Navigation',
      AppLang.bm: 'Mula Navigasi',
      AppLang.zh: '开始导航',
    },
    'arrived_btn': {
      AppLang.en: 'Arrived',
      AppLang.bm: 'Tiba',
      AppLang.zh: '已到达',
    },
    'replay_guidance': {
      AppLang.en: 'Replay arrow guidance',
      AppLang.bm: 'Ulang panduan anak panah',
      AppLang.zh: '重播路线指引',
    },
    'continue_to_btn': {
      AppLang.en: 'Continue to',
      AppLang.bm: 'Teruskan ke',
      AppLang.zh: '继续前往',
    },
    'nav_journey_complete': {
      AppLang.en: 'Journey complete!',
      AppLang.bm: 'Perjalanan selesai!',
      AppLang.zh: '行程已全部完成！',
    },
    'nav_turn_right': {
      AppLang.en: 'At the next corner, turn right',
      AppLang.bm: 'Di selekoh seterusnya, belok kanan',
      AppLang.zh: '在前方路口右转',
    },
    'nav_turn_left': {
      AppLang.en: 'At the next corner, turn left',
      AppLang.bm: 'Di selekoh seterusnya, belok kiri',
      AppLang.zh: '在前方路口左转',
    },
    'nav_follow_arrows': {
      AppLang.en: 'Follow green arrows to',
      AppLang.bm: 'Ikut anak panah hijau ke',
      AppLang.zh: '跟随绿色箭头前往',
    },
    'nav_tap_arrived': {
      AppLang.en: 'At destination — tap Arrived',
      AppLang.bm: 'Di destinasi — ketik Tiba',
      AppLang.zh: '已到达目的地 — 请点击已到达',
    },
    'explore_map_and_stores': {
      AppLang.en: 'Explore Map and Stores',
      AppLang.bm: 'Teroka Peta dan Kedai',
      AppLang.zh: '探索商场地图与店铺',
    },

    // Directory & Search dialog
    'search_add_stores': {
      AppLang.en: 'Search & Add Stores',
      AppLang.bm: 'Cari & Tambah Kedai',
      AppLang.zh: '搜索与添加店铺',
    },
    'search_store_hint': {
      AppLang.en: 'Search store, category or keyword',
      AppLang.bm: 'Cari kedai, kategori atau kata kunci',
      AppLang.zh: '搜索店铺、分类或关键字',
    },
    'tap_search_stores': {
      AppLang.en: 'Tap to search stores or lot numbers',
      AppLang.bm: 'Ketik untuk cari kedai atau no. lot',
      AppLang.zh: '点击搜索店铺或门牌号',
    },
    'stores_selected_suffix': {
      AppLang.en: 'stores selected',
      AppLang.bm: 'kedai dipilih',
      AppLang.zh: '已选择店铺',
    },
    'services_selected_suffix': {
      AppLang.en: 'services',
      AppLang.bm: 'kemudahan',
      AppLang.zh: '项公共设施',
    },
    'public_services': {
      AppLang.en: 'Public Services',
      AppLang.bm: 'Kemudahan Awam',
      AppLang.zh: '公共设施',
    },
    'change_start_pin': {
      AppLang.en: 'Change Start Pin',
      AppLang.bm: 'Tukar Titik Mula',
      AppLang.zh: '修改起点',
    },
    'pin_my_start': {
      AppLang.en: 'Pin My Start',
      AppLang.bm: 'Pilih Titik Mula',
      AppLang.zh: '标记起点',
    },
    'select_facility_hint': {
      AppLang.en: 'Select a facility to find it on the map or add it to your route.',
      AppLang.bm: 'Pilih kemudahan untuk cari di peta atau tambah ke laluan anda.',
      AppLang.zh: '选择设施以在地图上查看或加入您的路线。',
    },
    'search_services_hint': {
      AppLang.en: 'Search public services or locations',
      AppLang.bm: 'Cari kemudahan awam atau lokasi',
      AppLang.zh: '搜索公共设施或地点',
    },
    'locations_suffix': {
      AppLang.en: 'locations',
      AppLang.bm: 'lokasi',
      AppLang.zh: '处地点',
    },
    'svc_drop_off': {
      AppLang.en: 'Drop Off',
      AppLang.bm: 'Kawasan Menurunkan Penumpang',
      AppLang.zh: '落客接送区',
    },
    'svc_toilet': {
      AppLang.en: 'Toilets',
      AppLang.bm: 'Tandas',
      AppLang.zh: '卫生间',
    },
    'svc_nursing_room': {
      AppLang.en: 'Nursing Room',
      AppLang.bm: 'Bilik Penyusuan',
      AppLang.zh: '母婴室',
    },
    'svc_atm': {
      AppLang.en: 'ATM',
      AppLang.bm: 'ATM',
      AppLang.zh: '自动提款机 (ATM)',
    },
    'svc_surau': {
      AppLang.en: 'Surau',
      AppLang.bm: 'Surau',
      AppLang.zh: '祈祷室 (Surau)',
    },
    'svc_information': {
      AppLang.en: 'Information Counter',
      AppLang.bm: 'Kaunter Maklumat',
      AppLang.zh: '服务咨询台',
    },
    'svc_playground': {
      AppLang.en: "Children's Playground",
      AppLang.bm: 'Taman Permainan Kanak-kanak',
      AppLang.zh: '儿童游乐场',
    },
    'svc_other': {
      AppLang.en: 'Other Facilities',
      AppLang.bm: 'Kemudahan Lain',
      AppLang.zh: '其他设施',
    },
    'facility_disclaimer': {
      AppLang.en: 'Facility marker positions were estimated from the floor-plan symbols. Confirm entrances on site before publishing.',
      AppLang.bm: 'Kedudukan penanda kemudahan dianggarkan daripada simbol pelan lantai. Sila sahkan pintu masuk di lokasi sebenar.',
      AppLang.zh: '设施标记位置为平面图估算位置，请以现场实际出入口为准。',
    },
    'map_only': {
      AppLang.en: 'map only',
      AppLang.bm: 'peta sahaja',
      AppLang.zh: '仅在地图显示',
    },
    'find_on_map': {
      AppLang.en: 'Find on map',
      AppLang.bm: 'Cari di peta',
      AppLang.zh: '在地图上查看',
    },
    'add_to_route': {
      AppLang.en: 'Add to route',
      AppLang.bm: 'Tambah ke laluan',
      AppLang.zh: '加入路线',
    },
    'remove_from_route': {
      AppLang.en: 'Remove from route',
      AppLang.bm: 'Keluarkan dari laluan',
      AppLang.zh: '从路线移除',
    },
    'pedestrian_not_mapped': {
      AppLang.en: 'Pedestrian route not mapped',
      AppLang.bm: 'Laluan pejalan kaki belum dipetakan',
      AppLang.zh: '未绘制行人路线',
    },
    'pedestrian_path_not_mapped_desc': {
      AppLang.en: 'The pedestrian path to this facility has not been mapped yet.',
      AppLang.bm: 'Laluan pejalan kaki ke kemudahan ini belum dipetakan.',
      AppLang.zh: '前往此设施的行人通道尚未绘制。',
    },
    'no_matching_services': {
      AppLang.en: 'No matching services',
      AppLang.bm: 'Tiada kemudahan yang sepadan',
      AppLang.zh: '未找到匹配的公共设施',
    },
    'show_on_map': {
      AppLang.en: 'Show on Map',
      AppLang.bm: 'Tunjukkan di Peta',
      AppLang.zh: '在地图上查看',
    },
    'ground_floor_label': {
      AppLang.en: 'Ground Floor',
      AppLang.bm: 'Aras Bawah (GF)',
      AppLang.zh: '地面层 (GF)',
    },
    'tap_for_details': {
      AppLang.en: 'Tap for details',
      AppLang.bm: 'Ketik untuk butiran',
      AppLang.zh: '轻触查看详情',
    },
    'added_destinations': {
      AppLang.en: 'Added Destinations',
      AppLang.bm: 'Destinasi Ditambah',
      AppLang.zh: '已添加目的地',
    },
    'drag_reorder_hint': {
      AppLang.en: 'Drag to change the visit order, or remove a destination. Your changes are applied only after you tap OK & Generate Path.',
      AppLang.bm: 'Seret untuk mengubah urutan lawatan, atau padam destinasi. Perubahan akan disimpan selepas anda mengetik OK & Jana Laluan.',
      AppLang.zh: '拖拽可调整游览顺序，或删除目的地。点击“确定并生成路线”后生效。',
    },
    'no_destinations_left': {
      AppLang.en: 'No destinations left. Cancel to keep your selections, or add more destinations from search.',
      AppLang.bm: 'Tiada destinasi lagi. Batal untuk mengekalkan pilihan anda, atau tambah lagi destinasi.',
      AppLang.zh: '没有目的地。取消以保留当前选择，或从搜索中添加更多目的地。',
    },
    'public_service_label': {
      AppLang.en: 'Public service',
      AppLang.bm: 'Kemudahan awam',
      AppLang.zh: '公共设施',
    },
    'remove_destination': {
      AppLang.en: 'Remove destination',
      AppLang.bm: 'Padam destinasi',
      AppLang.zh: '删除目的地',
    },
    'btn_cancel': {
      AppLang.en: 'Cancel',
      AppLang.bm: 'Batal',
      AppLang.zh: '取消',
    },
    'btn_ok_generate_path': {
      AppLang.en: 'OK & Generate Path',
      AppLang.bm: 'OK & Jana Laluan',
      AppLang.zh: '确定并生成路线',
    },
    'destination_label': {
      AppLang.en: 'Destination',
      AppLang.bm: 'Destinasi',
      AppLang.zh: '目的地',
    },
    'ready_to_visit': {
      AppLang.en: 'Ready to visit',
      AppLang.bm: 'Bersedia untuk ke',
      AppLang.zh: '准备前往',
    },
    'itinerary_completed': {
      AppLang.en: 'Itinerary Completed!',
      AppLang.bm: 'Perjalanan Selesai!',
      AppLang.zh: '行程已全部完成！',
    },
    'itinerary_completed_msg': {
      AppLang.en: 'You have successfully visited all scheduled destinations!\nSelected shops and services are highlighted on the map.',
      AppLang.bm: 'Anda telah berjaya melawat semua destinasi yang dijadualkan!\nKedai dan perkhidmatan yang dipilih ditonjolkan pada peta.',
      AppLang.zh: '您已成功游览所有预定目的地！\n选定的店铺与公共设施已在地图上高亮显示。',
    },
    'btn_done': {
      AppLang.en: 'Done',
      AppLang.bm: 'Selesai',
      AppLang.zh: '完成',
    },
    // Pinned start label
    'pinned_start_label': {
      AppLang.en: 'Pinned on Ground Floor map',
      AppLang.bm: 'Ditandakan pada peta Aras Bawah',
      AppLang.zh: '已在地面层 (GF) 地图上标记',
    },

    // Continue exploring sheet
    'continue_exploring': {
      AppLang.en: 'Continue exploring?',
      AppLang.bm: 'Teruskan meneroka?',
      AppLang.zh: '继续探索更多店铺？',
    },
    'continue_exploring_desc': {
      AppLang.en: 'Only one planned shop remains. Add a few more matching stores, or finish the current journey.',
      AppLang.bm: 'Hanya satu kedai dirancang yang tinggal. Tambah beberapa lagi kedai, atau selesaikan perjalanan semasa.',
      AppLang.zh: '当前仅剩最后一家计划店铺。您可以添加更多心仪店铺，或结束当前行程。',
    },
    'new_category_mix': {
      AppLang.en: 'New category mix',
      AppLang.bm: 'Campuran kategori baharu',
      AppLang.zh: '新分类组合',
    },
    'no_more_matches': {
      AppLang.en: 'No more reachable matches for these interests.',
      AppLang.bm: 'Tiada lagi kedai yang sepadan untuk minat ini.',
      AppLang.zh: '未找到更多符合当前兴趣的店铺。',
    },
    'unlock_shop': {
      AppLang.en: 'Unlock shop',
      AppLang.bm: 'Buka kunci kedai',
      AppLang.zh: '解锁店铺',
    },
    'keep_when_shuffling': {
      AppLang.en: 'Keep when shuffling',
      AppLang.bm: 'Kekalkan semasa rawak',
      AppLang.zh: '换一批时保留此店铺',
    },
    'shuffle_suggestions': {
      AppLang.en: 'Shuffle suggestions',
      AppLang.bm: 'Rawak cadangan',
      AppLang.zh: '换一批推荐',
    },
    'finish_current_journey': {
      AppLang.en: 'Finish current journey',
      AppLang.bm: 'Selesai perjalanan semasa',
      AppLang.zh: '结束当前行程',
    },
    'btn_add_prefix': {
      AppLang.en: 'Add ',
      AppLang.bm: 'Tambah ',
      AppLang.zh: '添加 ',
    },
    'btn_add_shops_suffix': {
      AppLang.en: ' shops',
      AppLang.bm: ' kedai',
      AppLang.zh: ' 家店铺',
    },

    // Status banner
    'status_arrival_confirm': {
      AppLang.en: 'Arrival confirmation',
      AppLang.bm: 'Pengesahan ketibaan',
      AppLang.zh: '确认已到达',
    },
    'status_ready_next': {
      AppLang.en: 'Ready for next stop',
      AppLang.bm: 'Sedia untuk ke hentian seterusnya',
      AppLang.zh: '准备前往下一站',
    },
    'status_animated_demo': {
      AppLang.en: 'Animated route demo',
      AppLang.bm: 'Demo laluan animasi',
      AppLang.zh: '路线动画演示',
    },

    // Map store action card
    'btn_add_to_route': {
      AppLang.en: 'Add to Route',
      AppLang.bm: 'Tambah ke Laluan',
      AppLang.zh: '加入路线',
    },
    'finding_path': {
      AppLang.en: 'Finding path...',
      AppLang.bm: 'Mencari laluan...',
      AppLang.zh: '正在规划路线...',
    },
    'pin_start_and_generate_path': {
      AppLang.en: 'Pin your location, choose destinations, then Generate Path',
      AppLang.bm: 'Pilih lokasi anda, pilih destinasi, kemudian Jana Laluan',
      AppLang.zh: '标记起点并选择目的地，然后点击生成路线',
    },
    'stop_selected_prefix': {
      AppLang.en: 'Selected (Stop ',
      AppLang.bm: 'Dipilih (Hentian ',
      AppLang.zh: '已加入（第 ',
    },
    'stop_selected_suffix': {
      AppLang.en: ')',
      AppLang.bm: ')',
      AppLang.zh: ' 站）',
    },

    // Route Mode Dialog
    'generate_walking_path_title': {
      AppLang.en: 'Generate your walking path',
      AppLang.bm: 'Jana laluan berjalan kaki anda',
      AppLang.zh: '生成您的步行路线',
    },
    'generate_walking_path_desc': {
      AppLang.en: 'Start from your pinned location. Choose My sequence to review and reorder your added shops, or let MallPilot find the shortest path.',
      AppLang.bm: 'Bermula dari lokasi yang anda tetapkan. Pilih Urutan saya untuk menyemak dan menyusun semula kedai, atau biar MallPilot mencari laluan terpantas.',
      AppLang.zh: '从您标记的起点出发。选择“自定义顺序”可查看并调整店铺游览次序，或让 MallPilot 为您计算最短路线。',
    },
    'btn_my_sequence': {
      AppLang.en: 'My sequence',
      AppLang.bm: 'Urutan saya',
      AppLang.zh: '自定义顺序',
    },
    'btn_shortest_path': {
      AppLang.en: 'Shortest path',
      AppLang.bm: 'Laluan terpendek',
      AppLang.zh: '最短路线',
    },
    'sim_speed_title': {
      AppLang.en: 'Simulation playback speed',
      AppLang.bm: 'Kelajuan simulasi',
      AppLang.zh: '模拟导航播放速度',
    },
    'sim_speed_desc': {
      AppLang.en: 'This changes the animated preview, not physical walking speed.',
      AppLang.bm: 'Ini menukar kelajuan pratonton animasi, bukan kelajuan berjalan fizikal.',
      AppLang.zh: '此设置仅调整动画演示速度，并非实际步行速度。',
    },
    'only_gf_destinations_routed': {
      AppLang.en: 'Only mapped Ground Floor destinations can be routed.',
      AppLang.bm: 'Hanya destinasi Aras Bawah (GF) yang dipetakan boleh dirancang.',
      AppLang.zh: '当前仅支持已绘制步行网络的地面层 (GF) 目的地。',
    },
    'change_route_label': {
      AppLang.en: 'Change Route',
      AppLang.bm: 'Tukar Laluan',
      AppLang.zh: '修改路线',
    },
    'demo_paused_msg': {
      AppLang.en: 'Demo paused — tap Play above to resume',
      AppLang.bm: 'Demo dijeda — ketik Main di atas untuk sambung',
      AppLang.zh: '演示已暂停 — 轻触上方播放键继续',
    },
    'follow_green_arrows_corridor': {
      AppLang.en: 'Follow the repeating green arrows on the corridor',
      AppLang.bm: 'Ikuti anak panah hijau di laluan pejalan kaki',
      AppLang.zh: '沿走道上的绿色指示箭头前行',
    },
    'transit_guide': {
      AppLang.en: 'Transit Guide',
      AppLang.bm: 'Panduan Transit',
      AppLang.zh: '跨楼层换乘指引',
    },
    'take_escalator_lift_hint': {
      AppLang.en: 'Please take escalator or lift to destination floor',
      AppLang.bm: 'Sila gunakan eskalator atau lif ke tingkat destinasi',
      AppLang.zh: '请乘扶梯或电梯前往目标楼层',
    },
    'arrived_at_floor': {
      AppLang.en: 'I Have Arrived at',
      AppLang.bm: 'Saya telah tiba di',
      AppLang.zh: '我已到达',
    },
    'continuing_route': {
      AppLang.en: 'Continuing route to destination ➔',
      AppLang.bm: 'Meneruskan laluan ke destinasi ➔',
      AppLang.zh: '继续前往目的地 ➔',
    },
    'store_directory_title': {
      AppLang.en: 'Store Directory',
      AppLang.bm: 'Direktori Kedai',
      AppLang.zh: '商场店铺目录',
    },
    'recommendation_footer_note': {
      AppLang.en: 'As you navigate, you may receive suggestions for more shops when one planned destination remains.',
      AppLang.bm: 'Semasa menavigasi, anda mungkin menerima cadangan kedai lain apabila tinggal satu destinasi.',
      AppLang.zh: '当行程仅剩最后一家计划店铺时，系统将为您推荐更多顺路好店。',
    },
    'btn_retry': {
      AppLang.en: 'Retry',
      AppLang.bm: 'Cuba lagi',
      AppLang.zh: '重试',
    },

    // Selected shops preview sheet (Directory)
    'selected_shops_title': {
      AppLang.en: 'Selected Shops',
      AppLang.bm: 'Kedai Dipilih',
      AppLang.zh: '已选店铺',
    },
    'btn_clear_all': {
      AppLang.en: 'Clear All',
      AppLang.bm: 'Kosongkan Semua',
      AppLang.zh: '清空全部',
    },
    'btn_remove': {
      AppLang.en: 'Remove',
      AppLang.bm: 'Padam',
      AppLang.zh: '移除',
    },
    'clear_all_selected_title': {
      AppLang.en: 'Clear all selected shops?',
      AppLang.bm: 'Kosongkan semua kedai dipilih?',
      AppLang.zh: '清空所有已选店铺？',
    },
    'clear_all_selected_desc': {
      AppLang.en: 'This will remove every selected shop from your planned route. You can add them again from the search results.',
      AppLang.bm: 'Ini akan memadamkan semua kedai dipilih dari laluan anda. Anda boleh menambahnya semula dari hasil carian.',
      AppLang.zh: '这将从您的规划路线中移除所有已选店铺。您可以随时从搜索中重新添加。',
    },
    'no_shops_selected': {
      AppLang.en: 'No shops selected yet.\nTap + beside a shop to add it.',
      AppLang.bm: 'Tiada kedai dipilih lagi.\nKetik + di sebelah kedai untuk menambah.',
      AppLang.zh: '尚未选择任何店铺。\n轻触店铺旁的 + 即可添加。',
    },
    'no_stores_found': {
      AppLang.en: 'No stores found',
      AppLang.bm: 'Tiada kedai dijumpai',
      AppLang.zh: '未找到匹配的店铺',
    },
    'filter_title': {
      AppLang.en: 'Filter',
      AppLang.bm: 'Penapis',
      AppLang.zh: '筛选',
    },
    'filter_category': {
      AppLang.en: 'Category',
      AppLang.bm: 'Kategori',
      AppLang.zh: '店铺分类',
    },
    'show_results': {
      AppLang.en: 'Show results',
      AppLang.bm: 'Tunjukkan hasil',
      AppLang.zh: '查看筛选结果',
    },
    'price_not_listed': {
      AppLang.en: 'Price not listed',
      AppLang.bm: 'Harga tidak disenaraikan',
      AppLang.zh: '未标价',
    },
    'tooltip_unlock_shop': {
      AppLang.en: 'Unlock shop',
      AppLang.bm: 'Buka kunci kedai',
      AppLang.zh: '解锁店铺',
    },
    'tooltip_keep_shuffling': {
      AppLang.en: 'Keep when shuffling',
      AppLang.bm: 'Kekalkan semasa rombak',
      AppLang.zh: '换一批时保留',
    },
    'tooltip_previous_step': {
      AppLang.en: 'Previous step',
      AppLang.bm: 'Langkah sebelumnya',
      AppLang.zh: '上一步',
    },
    'tooltip_close_preview': {
      AppLang.en: 'Close preview',
      AppLang.bm: 'Tutup pratonton',
      AppLang.zh: '关闭预览',
    },
    'tooltip_back_to_map': {
      AppLang.en: 'Back to indoor map',
      AppLang.bm: 'Kembali ke peta',
      AppLang.zh: '返回室内地图',
    },
    'tooltip_preview_selected': {
      AppLang.en: 'Preview selected shops',
      AppLang.bm: 'Pratonton kedai dipilih',
      AppLang.zh: '预览已选店铺',
    },
    'tooltip_remove_stop': {
      AppLang.en: 'Remove from planned stops',
      AppLang.bm: 'Keluarkan dari laluan',
      AppLang.zh: '从规划路线中移除',
    },
    'tooltip_add_stop': {
      AppLang.en: 'Add to planned stops',
      AppLang.bm: 'Tambah ke laluan',
      AppLang.zh: '添加到规划路线',
    },
    'select_start_location_title': {
      AppLang.en: 'Select Current Location (Start Point)',
      AppLang.bm: 'Pilih Lokasi Semasa (Titik Mula)',
      AppLang.zh: '选择当前位置（起点）',
    },
    'select_start_location_subtitle': {
      AppLang.en: 'Choose an entrance, or tap any store/facility on the map',
      AppLang.bm: 'Pilih pintu masuk, atau ketik kedai/kemudahan di peta',
      AppLang.zh: '选择出入口，或在地图上轻触任意店铺/设施',
    },
    'badge_recommended': {
      AppLang.en: 'RECOMMENDED',
      AppLang.bm: 'DISYORKAN',
      AppLang.zh: '推荐',
    },
    'public_facilities_quick_start': {
      AppLang.en: '🚻 Public Facilities & Lifts (Quick Start)',
      AppLang.bm: '🚻 Kemudahan Awam & Lif (Mula Pantas)',
      AppLang.zh: '🚻 公共设施与电梯（快捷起点）',
    },
    'start_point_set': {
      AppLang.en: 'Starting point set to',
      AppLang.bm: 'Titik permulaan ditetapkan ke',
      AppLang.zh: '起点已设置为',
    },
    'msg_1f_services_preview': {
      AppLang.en: 'First-floor services are preview-only until 1F routing is ready.',
      AppLang.bm: 'Perkhidmatan Aras 1 adalah untuk pratonton sahaja sehingga laluan Aras 1 siap.',
      AppLang.zh: '一楼设施服务目前仅供预览，暂未开放导航路线。',
    },
    'msg_lot_not_in_directory': {
      AppLang.en: 'This lot is not available in the store directory.',
      AppLang.bm: 'Lot ini tiada dalam direktori kedai.',
      AppLang.zh: '该商铺单位未在商铺目录中列出。',
    },
    'msg_only_gf_routing': {
      AppLang.en: 'Only Ground Floor routing is supported.',
      AppLang.bm: 'Hanya laluan Aras Bawah (GF) disokong buat masa ini.',
      AppLang.zh: '目前仅支持地面层 (GF) 路径导航。',
    },
    'msg_shop_not_in_directory': {
      AppLang.en: 'This shop is not in the directory.',
      AppLang.bm: 'Kedai ini tiada dalam direktori.',
      AppLang.zh: '该店铺未在商铺目录中。',
    },
    'msg_routing_first_shop': {
      AppLang.en: 'Routing starts from your first selected Ground Floor stop.',
      AppLang.bm: 'Laluan bermula dari hentian Aras Bawah pertama anda.',
      AppLang.zh: '路线从您选中的第一个地面层站点开始。',
    },
    'msg_set_start_before_route': {
      AppLang.en: 'Set your starting location with Pin My Start before generating a route.',
      AppLang.bm: 'Sila tetapkan titik mula dengan Tanda Titik Mula sebelum menjana laluan.',
      AppLang.zh: '生成路线前，请先使用“标记我的起点”设置出发位置。',
    },
    'msg_choose_up_to_10': {
      AppLang.en: 'Choose up to 10 mapped Ground Floor destinations.',
      AppLang.bm: 'Pilih sehingga 10 destinasi Aras Bawah yang dipetakan.',
      AppLang.zh: '最多可选择 10 个已标记的地面层目的地。',
    },
    'msg_add_destination_first': {
      AppLang.en: 'Add at least one shop or public service first.',
      AppLang.bm: 'Sila tambah sekurang-kurangnya satu kedai atau perkhidmatan awam dahulu.',
      AppLang.zh: '请先添加至少一家店铺或公共服务设施。',
    },
    'msg_generate_route_first': {
      AppLang.en: 'Generate a route with destination stops before navigating.',
      AppLang.bm: 'Sila jana laluan sebelum memulakan navigasi.',
      AppLang.zh: '开始导航前，请先生成包含目的地的路线。',
    },
    'msg_only_gf_stores_route': {
      AppLang.en: 'Only mapped Ground Floor stores can be added to a route.',
      AppLang.bm: 'Hanya kedai Aras Bawah yang dipetakan boleh ditambah ke laluan.',
      AppLang.zh: '仅地面层已标记商铺可加入导航路线。',
    },
    'msg_no_entrance_node': {
      AppLang.en: 'This store has no mapped entrance node yet.',
      AppLang.bm: 'Kedai ini belum mempunyai nod pintu masuk dipetakan.',
      AppLang.zh: '该店铺暂无标注入门点。',
    },
    'msg_no_polygon': {
      AppLang.en: 'This store has no traced polygon yet.',
      AppLang.bm: 'Kedai ini belum mempunyai poligon dipetakan.',
      AppLang.zh: '该店铺暂无轮廓数据。',
    },
    'view_on_map': {
      AppLang.en: 'View on map',
      AppLang.bm: 'Lihat pada peta',
      AppLang.zh: '在地图上查看',
    },
    'selected_destinations': {
      AppLang.en: 'Selected Destinations',
      AppLang.bm: 'Destinasi Dipilih',
      AppLang.zh: '已选目的地',
    },
    'stores_unit': {
      AppLang.en: 'Stores',
      AppLang.bm: 'Kedai',
      AppLang.zh: '间店铺',
    },
    'btn_clear_route': {
      AppLang.en: 'Clear Route',
      AppLang.bm: 'Kosongkan Laluan',
      AppLang.zh: '清空路线',
    },
    'btn_add': {
      AppLang.en: 'Add',
      AppLang.bm: 'Tambah',
      AppLang.zh: '添加',
    },
    'btn_added': {
      AppLang.en: 'Added',
      AppLang.bm: 'Ditambah',
      AppLang.zh: '已添加',
    },
    'add_destinations_hint': {
      AppLang.en: 'Add shops or public services to visit',
      AppLang.bm: 'Tambah kedai atau kemudahan awam untuk dilawati',
      AppLang.zh: '添加您想前往的店铺或公共服务设施',
    },
    'finding_corridor_routes': {
      AppLang.en: 'Finding corridor routes from your pinned position...',
      AppLang.bm: 'Mencari laluan dari titik mula anda...',
      AppLang.zh: '正在从您的起点规划路线...',
    },
    'route_unavailable': {
      AppLang.en: 'Route unavailable',
      AppLang.bm: 'Laluan tidak tersedia',
      AppLang.zh: '无法规划路线',
    },
    'updating_route_from_pin': {
      AppLang.en: 'Updating route from the new start pin...',
      AppLang.bm: 'Mengemas kini laluan dari titik mula baharu...',
      AppLang.zh: '正在根据新起点更新路线...',
    },
  };

  static const Map<String, Map<AppLang, String>> _subCategoryTranslations = {
    'Baby & Kids Products': {
      AppLang.en: 'Baby & Kids Products',
      AppLang.bm: 'Produk Bayi & Kanak-kanak',
      AppLang.zh: '母婴童品',
    },
    'Bag Care & Repair': {
      AppLang.en: 'Bag Care & Repair',
      AppLang.bm: 'Penjagaan & Pembaikan Beg',
      AppLang.zh: '包包护理与维修',
    },
    'Bakery & Cakes': {
      AppLang.en: 'Bakery & Cakes',
      AppLang.bm: 'Bakeri & Kek',
      AppLang.zh: '烘焙糕点',
    },
    'Beverages & Cafe': {
      AppLang.en: 'Beverages & Cafe',
      AppLang.bm: 'Minuman & Kafe',
      AppLang.zh: '咖啡饮品',
    },
    'Bicycles & Cycling Gear': {
      AppLang.en: 'Bicycles & Cycling Gear',
      AppLang.bm: 'Basikal & Peralatan Berbasikal',
      AppLang.zh: '自行车与骑行装备',
    },
    'Books, Stationery & Library': {
      AppLang.en: 'Books, Stationery & Library',
      AppLang.bm: 'Buku & Alat Tulis',
      AppLang.zh: '图书文具与阅读',
    },
    'Casual Dining & Restaurant': {
      AppLang.en: 'Casual Dining & Restaurant',
      AppLang.bm: 'Restoran Santai',
      AppLang.zh: '休闲餐厅',
    },
    'Casual Wear & Apparel': {
      AppLang.en: 'Casual Wear & Apparel',
      AppLang.bm: 'Pakaian Santai',
      AppLang.zh: '休闲服饰',
    },
    'Convenience Store': {
      AppLang.en: 'Convenience Store',
      AppLang.bm: 'Kedai Serbaneka',
      AppLang.zh: '便利店',
    },
    'Cosmetics & Skincare': {
      AppLang.en: 'Cosmetics & Skincare',
      AppLang.bm: 'Kosmetik & Penjagaan Kulit',
      AppLang.zh: '美妆护肤',
    },
    'Dessert & Ice Cream': {
      AppLang.en: 'Dessert & Ice Cream',
      AppLang.bm: 'Pencuci Mulut & Aiskrim',
      AppLang.zh: '甜品与冰淇淋',
    },
    'Eyewear & Optical': {
      AppLang.en: 'Eyewear & Optical',
      AppLang.bm: 'Cermin Mata & Optik',
      AppLang.zh: '眼镜配镜',
    },
    'Fashion Accessories': {
      AppLang.en: 'Fashion Accessories',
      AppLang.bm: 'Aksesori Fesyen',
      AppLang.zh: '时尚配饰',
    },
    'Fast Food & Snacks': {
      AppLang.en: 'Fast Food & Snacks',
      AppLang.bm: 'Makanan Segera & Snek',
      AppLang.zh: '快餐小吃',
    },
    'Fitness & Gym': {
      AppLang.en: 'Fitness & Gym',
      AppLang.bm: 'Kecergasan & Gim',
      AppLang.zh: '健身房',
    },
    'Food & Beverages': {
      AppLang.en: 'Food & Beverages',
      AppLang.bm: 'Makanan & Minuman',
      AppLang.zh: '餐饮美食',
    },
    'Footwear & Shoes': {
      AppLang.en: 'Footwear & Shoes',
      AppLang.bm: 'Kasut & Alas Kaki',
      AppLang.zh: '鞋履专卖',
    },
    'Fragrance': {
      AppLang.en: 'Fragrance',
      AppLang.bm: 'Minyak Wangi',
      AppLang.zh: '香水香氛',
    },
    'Gadgets & Electronics': {
      AppLang.en: 'Gadgets & Electronics',
      AppLang.bm: 'Gajet & Elektronik',
      AppLang.zh: '数码电子',
    },
    'General Retail': {
      AppLang.en: 'General Retail',
      AppLang.bm: 'Peruncitan Am',
      AppLang.zh: '综合零售',
    },
    'Home & Variety Store': {
      AppLang.en: 'Home & Variety Store',
      AppLang.bm: 'Kedai Barangan Rumah',
      AppLang.zh: '家居百货',
    },
    'Home Appliances & Furniture': {
      AppLang.en: 'Home Appliances & Furniture',
      AppLang.bm: 'Perkakas Rumah & Perabot',
      AppLang.zh: '家电与家具',
    },
    'Indoor Playground': {
      AppLang.en: 'Indoor Playground',
      AppLang.bm: 'Taman Permainan Dalaman',
      AppLang.zh: '室内游乐场',
    },
    'Modest & Traditional Fashion': {
      AppLang.en: 'Modest & Traditional Fashion',
      AppLang.bm: 'Fesyen Tradisional & Sopan',
      AppLang.zh: '传统与穆斯林时尚',
    },
    'Nail & Beauty Services': {
      AppLang.en: 'Nail & Beauty Services',
      AppLang.bm: 'Perkhidmatan Kuku & Kecantikan',
      AppLang.zh: '美甲美睫护理',
    },
    'Pets & Aquarium': {
      AppLang.en: 'Pets & Aquarium',
      AppLang.bm: 'Haiwan Peliharaan & Akuarium',
      AppLang.zh: '宠物水族',
    },
    'Pharmacy & Personal Care': {
      AppLang.en: 'Pharmacy & Personal Care',
      AppLang.bm: 'Farmasi & Penjagaan Diri',
      AppLang.zh: '药妆个护',
    },
    'Property Sales Gallery': {
      AppLang.en: 'Property Sales Gallery',
      AppLang.bm: 'Galeri Jualan Hartanah',
      AppLang.zh: '楼盘展厅',
    },
    'Sports & Activewear': {
      AppLang.en: 'Sports & Activewear',
      AppLang.bm: 'Pakaian Sukan',
      AppLang.zh: '运动服饰',
    },
    'Supermarket & Fresh Groceries': {
      AppLang.en: 'Supermarket & Fresh Groceries',
      AppLang.bm: 'Pasaraya & Barangan Segar',
      AppLang.zh: '生鲜超市',
    },
    'Toys': {
      AppLang.en: 'Toys',
      AppLang.bm: 'Mainan',
      AppLang.zh: '玩具专卖',
    },
    'Waxing & Hair Removal': {
      AppLang.en: 'Waxing & Hair Removal',
      AppLang.bm: 'Penyingkiran Bulu',
      AppLang.zh: '脱毛护理',
    },
  };

  static const Map<String, Map<AppLang, String>> _facilityNameTranslations = {
    'Drop Off 1 – Sales Gallery': {
      AppLang.en: 'Drop Off 1 – Sales Gallery',
      AppLang.bm: 'Zon Menurunkan Penumpang 1 – Galeri Jualan',
      AppLang.zh: '落客区 1 – 楼盘展厅',
    },
    'Drop Off 2 – South Central': {
      AppLang.en: 'Drop Off 2 – South Central',
      AppLang.bm: 'Zon Menurunkan Penumpang 2 – Tengah Selatan',
      AppLang.zh: '落客区 2 – 中南侧',
    },
    'Drop Off 3 – Central East': {
      AppLang.en: 'Drop Off 3 – Central East',
      AppLang.bm: 'Zon Menurunkan Penumpang 3 – Tengah Timur',
      AppLang.zh: '落客区 3 – 中东侧',
    },
    'Drop Off 4 – East': {
      AppLang.en: 'Drop Off 4 – East',
      AppLang.bm: 'Zon Menurunkan Penumpang 4 – Timur',
      AppLang.zh: '落客区 4 – 东侧',
    },
    'Toilet 1 – Southwest': {
      AppLang.en: 'Toilet 1 – Southwest',
      AppLang.bm: 'Tandas 1 – Barat Daya',
      AppLang.zh: '卫生间 1 – 西南侧',
    },
    'Toilet 2 – Central': {
      AppLang.en: 'Toilet 2 – Central',
      AppLang.bm: 'Tandas 2 – Tengah',
      AppLang.zh: '卫生间 2 – 中央区',
    },
    'Nursing Room – Central': {
      AppLang.en: 'Nursing Room – Central',
      AppLang.bm: 'Bilik Penyusuan – Tengah',
      AppLang.zh: '母婴室 – 中央区',
    },
    'ATM – Central': {
      AppLang.en: 'ATM – Central',
      AppLang.bm: 'ATM – Tengah',
      AppLang.zh: '自动提款机 (ATM) – 中央区',
    },
    'Surau – Central': {
      AppLang.en: 'Surau – Central',
      AppLang.bm: 'Surau – Tengah',
      AppLang.zh: '祈祷室 – 中央区',
    },
    'Information Counter – South': {
      AppLang.en: 'Information Counter – South',
      AppLang.bm: 'Kaunter Maklumat – Selatan',
      AppLang.zh: '服务咨询台 – 南侧',
    },
    "Children's Playground – Southeast": {
      AppLang.en: "Children's Playground – Southeast",
      AppLang.bm: 'Taman Permainan Kanak-kanak – Tenggara',
      AppLang.zh: '儿童游乐场 – 东南侧',
    },
  };

  static const Map<String, Map<AppLang, String>> _facilityDescTranslations = {
    'Near the Integrated Operations Office and Sales Gallery': {
      AppLang.en: 'Near the Integrated Operations Office and Sales Gallery',
      AppLang.bm: 'Berhampiran Pejabat Operasi Bersepadu dan Galeri Jualan',
      AppLang.zh: '靠近综合运营办公室与楼盘展厅',
    },
    'Near GF-01 and the south-central entrance': {
      AppLang.en: 'Near GF-01 and the south-central entrance',
      AppLang.bm: 'Berhampiran GF-01 dan pintu masuk tengah selatan',
      AppLang.zh: '靠近 GF-01 及中南侧主入口',
    },
    'Near GF-25 and the central eastern entrance': {
      AppLang.en: 'Near GF-25 and the central eastern entrance',
      AppLang.bm: 'Berhampiran GF-25 dan pintu masuk tengah timur',
      AppLang.zh: '靠近 GF-25 及中东侧入口',
    },
    'Near the GF-88 & GF-89 side entrance': {
      AppLang.en: 'Near the GF-88 & GF-89 side entrance',
      AppLang.bm: 'Berhampiran pintu masuk sisi GF-88 & GF-89',
      AppLang.zh: '靠近 GF-88 与 GF-89 侧门入口',
    },
    'Southwest toilet area near GF-80; both male and female symbols represent this one location': {
      AppLang.en: 'Southwest toilet area near GF-80; both male and female symbols represent this one location',
      AppLang.bm: 'Kawasan tandas barat daya berhampiran GF-80; simbol lelaki dan wanita mewakili lokasi ini',
      AppLang.zh: '位于 GF-80 附近的西南侧洗手间区（男女通用位置）',
    },
    'Central toilet area near GF-52; both male and female symbols represent this one location': {
      AppLang.en: 'Central toilet area near GF-52; both male and female symbols represent this one location',
      AppLang.bm: 'Kawasan tandas tengah berhampiran GF-52; simbol lelaki dan wanita mewakili lokasi ini',
      AppLang.zh: '位于 GF-52 附近的中央洗手间区（男女通用位置）',
    },
    'Next to the central toilet area': {
      AppLang.en: 'Next to the central toilet area',
      AppLang.bm: 'Bersebelahan kawasan tandas tengah',
      AppLang.zh: '紧邻中央洗手间区',
    },
    'ATM near the central facilities area': {
      AppLang.en: 'ATM near the central facilities area',
      AppLang.bm: 'ATM berhampiran kawasan kemudahan pusat',
      AppLang.zh: '位于中央公共设施区的自动提款机',
    },
    'Prayer room near the central facilities area': {
      AppLang.en: 'Prayer room near the central facilities area',
      AppLang.bm: 'Bilik solat berhampiran kawasan kemudahan pusat',
      AppLang.zh: '位于中央公共设施区的穆斯林祈祷室',
    },
    'Near the water feature and south-central shops': {
      AppLang.en: 'Near the water feature and south-central shops',
      AppLang.bm: 'Berhampiran pancuran air dan kedai tengah selatan',
      AppLang.zh: '靠近水景喷泉及中南侧商铺',
    },
    'Near the southeast shopping area and water feature': {
      AppLang.en: 'Near the southeast shopping area and water feature',
      AppLang.bm: 'Berhampiran kawasan beli-belah tenggara dan pancuran air',
      AppLang.zh: '靠近东南侧购物区与亲水景观',
    },
  };

  static const Map<String, Map<AppLang, String>> _categoryTranslations = {
    'Food & Drinks': {
      AppLang.en: 'Food & Drinks',
      AppLang.bm: 'Makanan & Minuman',
      AppLang.zh: '餐饮美食',
    },
    'Fashion': {
      AppLang.en: 'Fashion',
      AppLang.bm: 'Fesyen',
      AppLang.zh: '时尚服饰',
    },
    'Beauty & Care': {
      AppLang.en: 'Beauty & Care',
      AppLang.bm: 'Kecantikan & Penjagaan',
      AppLang.zh: '美容护理',
    },
    'Electronics': {
      AppLang.en: 'Electronics',
      AppLang.bm: 'Elektronik',
      AppLang.zh: '数码家电',
    },
    'Sports': {
      AppLang.en: 'Sports',
      AppLang.bm: 'Sukan',
      AppLang.zh: '运动户外',
    },
    'Sportswear': {
      AppLang.en: 'Sportswear',
      AppLang.bm: 'Pakaian Sukan',
      AppLang.zh: '运动服饰',
    },
    'Home & Lifestyle': {
      AppLang.en: 'Home & Lifestyle',
      AppLang.bm: 'Gaya Hidup & Rumah',
      AppLang.zh: '家居生活',
    },
    'Groceries': {
      AppLang.en: 'Groceries',
      AppLang.bm: 'Barangan Runcit',
      AppLang.zh: '超市生鲜',
    },
    'Accessories': {
      AppLang.en: 'Accessories',
      AppLang.bm: 'Aksesori',
      AppLang.zh: '钟表饰品',
    },
    'Entertainment': {
      AppLang.en: 'Entertainment',
      AppLang.bm: 'Hiburan',
      AppLang.zh: '休闲娱乐',
    },
    'Food & Beverage': {
      AppLang.en: 'Food & Beverage',
      AppLang.bm: 'Makanan & Minuman',
      AppLang.zh: '餐饮美食',
    },
    'Department Store & Supermarket': {
      AppLang.en: 'Department Store & Supermarket',
      AppLang.bm: 'Gedung Membeli-belah & Pasar Raya',
      AppLang.zh: '百货与超市',
    },
    'Health & Beauty': {
      AppLang.en: 'Health & Beauty',
      AppLang.bm: 'Kesihatan & Kecantikan',
      AppLang.zh: '美妆个护',
    },
    'Services': {
      AppLang.en: 'Services',
      AppLang.bm: 'Perkhidmatan',
      AppLang.zh: '生活服务',
    },
    'Specialty': {
      AppLang.en: 'Specialty',
      AppLang.bm: 'Kedai Khas',
      AppLang.zh: '特色专卖',
    },
  };
}

/// Frosted-glass 3-language switch pill [ EN | BM | 中文 ]
class LanguageSwitchCapsule extends StatelessWidget {
  const LanguageSwitchCapsule({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLang>(
      valueListenable: AppLanguage.current,
      builder: (context, currentLang, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 4.0, sigmaY: 4.0),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0x33000000),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0x44FFFFFF), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildOption(context, AppLang.en, 'EN', currentLang),
                  const SizedBox(width: 2),
                  Container(width: 1, height: 12, color: const Color(0x33FFFFFF)),
                  const SizedBox(width: 2),
                  _buildOption(context, AppLang.bm, 'BM', currentLang),
                  const SizedBox(width: 2),
                  Container(width: 1, height: 12, color: const Color(0x33FFFFFF)),
                  const SizedBox(width: 2),
                  _buildOption(context, AppLang.zh, '中文', currentLang),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOption(
    BuildContext context,
    AppLang lang,
    String label,
    AppLang activeLang,
  ) {
    final isSelected = lang == activeLang;
    return GestureDetector(
      onTap: () => AppLanguage.setLanguage(lang),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0x50FFFFFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? const Color(0x80FFFFFF) : Colors.transparent,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  const BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0.2,
            color: isSelected ? Colors.white : const Color(0xB8FFFFFF),
          ),
        ),
      ),
    );
  }
}
