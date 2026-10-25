/**
 * 旧版 Flutter 项目的非 UI 常量，1:1 移植（只读参考 ~/Projects/njuschedule）。
 *
 * 来源：
 * - lib/Resources/Constant.dart
 * - lib/Resources/Config.dart
 * - lib/Resources/Url.dart
 * - lib/Resources/Colors.dart
 *
 * 这些值属于「其余部分沿用旧项目」的契约：改动会破坏与旧数据的兼容性。
 */

/** 一节课的起止时间（`HH:mm`）。 */
export class ClassPeriod {
  start: string;
  end: string;

  constructor(start: string, end: string) {
    this.start = start;
    this.end = end;
  }
}

/** 旧版 Constant.dart 的常量。 */
export class LegacyConstant {
  /** 下标 0 为占位，1-7 对应周一至周日（旧版 _getIntWeek 依赖该偏移）。 */
  static readonly WEEK_WITH_BIAS: string[] = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  static readonly WEEK_WITHOUT_BIAS: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  static readonly WEEK_WITHOUT_BIAS_WITHOUT_PRE: string[] = ['一', '二', '三', '四', '五', '六', '日'];

  /** 默认作息（南大本部），课表 data.class_time_list 为空时使用。 */
  static readonly CLASS_TIME_LIST: ClassPeriod[] = [
    new ClassPeriod('08:00', '08:50'),
    new ClassPeriod('09:00', '09:50'),
    new ClassPeriod('10:10', '11:00'),
    new ClassPeriod('11:10', '12:00'),
    new ClassPeriod('14:00', '14:50'),
    new ClassPeriod('15:00', '15:50'),
    new ClassPeriod('16:10', '17:00'),
    new ClassPeriod('17:10', '18:00'),
    new ClassPeriod('18:30', '19:20'),
    new ClassPeriod('19:30', '20:20'),
    new ClassPeriod('20:30', '21:20'),
    new ClassPeriod('21:30', '22:20'),
    new ClassPeriod('22:30', '23:59')
  ];

  static readonly LOGIN_CORRECT: number = 0;
  static readonly PASSWORD_ERROR: number = 1;
  static readonly CAPTCHA_ERROR: number = 2;
  static readonly USERNAME_ERROR: number = 3;

  /** course.import_type */
  static readonly ADD_MANUALLY: number = 0;
  static readonly ADD_BY_IMPORT: number = 1;
  static readonly ADD_BY_LECTURE: number = 2;

  static readonly DEFAULT_WEEK_START: number = 1;
  static readonly DEFAULT_WEEK_NUM: number = 17;
  static readonly DEFAULT_WEEK_END: number = LegacyConstant.DEFAULT_WEEK_NUM;

  static readonly FULL_WEEKS: number = 0;
  static readonly SINGLE_WEEKS: number = 1;
  static readonly DOUBLE_WEEKS: number = 2;
  static readonly DEFINED_WEEKS: number = 3;

}

/** 旧版 Config.dart 的常量。 */
export class LegacyConfig {
  static readonly MAX_CLASSES: number = 13;
  static readonly MAX_WEEKS: number = 25;
  static readonly DEFAULT_CLASS_TABLE: string = '默认课表';
  static readonly DONATE_DIALOG_DELAY_SECONDS: number = 10;
  static readonly REVIEW_DIALOG_DELAY_SECONDS: number = 10;
  static readonly REVIEW_DIALOG_SHOW_TIME: number = 10;
}

/** 旧版 Url.dart 的常量。外部域名与旧版完全一致，不新增。 */
export class LegacyUrl {
  static readonly NJU_HOST: string = 'http://elite.nju.edu.cn/jiaowu';
  static readonly CLASS_INFO: string = '/student/teachinginfo/courseList.do?method=currentTermCourse';
  static readonly LOGIN: string = '/login.do';
  static readonly NJU_VPN: string = 'https://vpn.nju.edu.cn';

  static readonly BACKEND: string = 'https://lecture.idealclover.cn';
  static readonly APPLE: string = 'https://pay.idealclover.cn/apple_new/2';
  static readonly ANDROID: string = 'https://pay.idealclover.cn/android_new/1';
  static readonly OHOS: string = 'https://pay.idealclover.cn/ohos_new/1';

  static readonly OPEN_SOURCE: string = 'https://github.com/WheretoSleepinNJU/NJU-Class-Shedule-Flutter';
  static readonly BLOG: string = 'https://idealclover.top';
  static readonly UPDATE_ROOT: string = 'https://cdn.idealclover.cn/Projects/wheretosleepinnju/production';
}

/** 旧版 Config.dart 里的两个内置导入配置（学校列表拉取失败时的兜底）。 */

/** 旧版 Colors.dart 的课程色池（14 色），顺序不可改。 */
export class LegacyCourseColors {
  static readonly COLOR_LIST: string[] = [
    '#8AD297',
    '#F9A883',
    '#88CFCC',
    '#F19C99',
    '#F7C56B',
    '#D2A596',
    '#67BDDE',
    '#9CCF5A',
    '#9AB4CF',
    '#E593AD',
    '#E2C38A',
    '#B29FD2',
    '#E2C490',
    '#E2C490'
  ];
}
