/**
 * 第三方许可证数据。
 *
 * 组件列表点击后直接用系统浏览器打开对应仓库/包管理器的许可证页面，
 * 不在应用内维护许可证全文副本。
 *
 * 收录范围（对比上游 Flutter 项目「关于 → 开源库」清单后筛选）：
 * 只收录上游项目使用、且本应用移植了对应能力的开源库；
 * 本应用为 ArkTS/ArkUI 重写，许可证与版权归原作者。
 */

/** 一个第三方组件及其许可证页面。 */
export class ThirdPartyLicense {
  name: string;
  license: string;
  licenseCount: number;
  /** 对应仓库/包管理器的许可证页面。 */
  url: string;
  copyright: string;

  constructor(name: string, license: string, licenseCount: number, url: string, copyright: string) {
    this.name = name;
    this.license = license;
    this.licenseCount = licenseCount;
    this.url = url;
    this.copyright = copyright;
  }
}

/** 实际使用/移植的开源组件（新增依赖时同步补充）。 */
export const THIRD_PARTY_LICENSES: ThirdPartyLicense[] = [
  new ThirdPartyLicense(
    '南哪课表（上游 Flutter 项目）',
    'Apache License 2.0',
    1,
    'https://github.com/WheretoSleepinNJU/NJU-Class-Shedule-Flutter/blob/master/LICENSE',
    'Copyright idealclover'
  ),
  new ThirdPartyLicense(
    'shared_preferences',
    'BSD-3-Clause',
    1,
    'https://pub.dev/packages/shared_preferences/license',
    'Copyright 2013 The Flutter Authors. All rights reserved.'
  ),
  new ThirdPartyLicense(
    'flutter_swiper_null_safety_flutter3',
    'MIT',
    1,
    'https://pub.dev/packages/flutter_swiper_null_safety_flutter3/license',
    'Copyright (c) 2018 Xueliang Ren'
  ),
  new ThirdPartyLicense(
    'webview_flutter',
    'BSD-3-Clause',
    1,
    'https://pub.dev/packages/webview_flutter/license',
    'Copyright 2013 The Flutter Authors. All rights reserved.'
  ),
  new ThirdPartyLicense(
    'image_picker',
    'BSD-3-Clause / Apache-2.0',
    2,
    'https://pub.dev/packages/image_picker/license',
    'Copyright 2013 The Flutter Authors. All rights reserved.'
  ),
  new ThirdPartyLicense(
    'package_info_plus',
    'BSD-3-Clause',
    1,
    'https://pub.dev/packages/package_info_plus/license',
    'Copyright 2017 The Chromium Authors. All rights reserved.'
  ),
  new ThirdPartyLicense(
    'path_provider',
    'BSD-3-Clause',
    1,
    'https://pub.dev/packages/path_provider/license',
    'Copyright 2013 The Flutter Authors. All rights reserved.'
  ),
  new ThirdPartyLicense(
    'fluttertoast',
    'MIT',
    1,
    'https://pub.dev/packages/fluttertoast/license',
    'Copyright (c) 2020 Karthik Ponnam'
  ),
  new ThirdPartyLicense(
    'sqflite',
    'BSD-2-Clause',
    1,
    'https://pub.dev/packages/sqflite/license',
    'Copyright (c) 2019, Alexandre Roux Tekartik'
  ),
  new ThirdPartyLicense(
    'dio',
    'MIT',
    1,
    'https://pub.dev/packages/dio/license',
    'Copyright (c) 2018 Wen Du (wendux)'
  ),
];
