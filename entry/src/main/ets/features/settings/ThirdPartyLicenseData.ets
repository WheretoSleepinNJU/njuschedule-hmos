/**
 * 第三方许可证数据。
 *
 * 组件列表点击后直接用系统浏览器打开对应仓库/包管理器的许可证页面，
 * 不在应用内维护许可证全文副本。
 *
 * 收录范围：只收录本应用实际分发或实际沿用代码的项目。
 * HarmonyOS / ArkUI、ArkWeb、Scan Kit 等为华为系统能力，不属于第三方开源库。
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
  )
];
