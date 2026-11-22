/**
 * 课程配色池预设。
 *
 * 默认沿用旧版 14 色；其余为低饱和/清透系：
 * - 莫兰迪：低饱和灰调；
 * - 水彩：清透水彩色系；
 * - 马卡龙：清甜低饱和。
 *
 * 课程最终颜色 = 当前色池按课表做多轮不放回分配后的色位。
 */
import { LegacyCourseColors } from '../common/Constants';

export class CourseColorPalette {
  id: string = '';
  name: string = '';
  subtitle: string = '';
  colors: string[] = [];

  constructor(id: string, name: string, subtitle: string, colors: string[]) {
    this.id = id;
    this.name = name;
    this.subtitle = subtitle;
    this.colors = colors;
  }
}

export class CourseColorPalettes {
  static readonly DEFAULT_ID: string = 'default';

  static readonly LIST: CourseColorPalette[] = [
    new CourseColorPalette('default', '默认', '应用现有配色', LegacyCourseColors.COLOR_LIST),
    new CourseColorPalette('morandi', '莫兰迪', '低饱和灰调', [
      '#A8B5A2', '#C7B8A8', '#B7A9A1', '#9DABB5', '#C4A69B', '#A9A29E',
      '#D0C4B2', '#8FA1A8', '#B8A7B0', '#C6BBAF', '#9AA79A', '#B0A8B8'
    ]),
    new CourseColorPalette('watercolor', '水彩', '清透低饱和', [
      '#7FB3D5', '#A8D5BA', '#F6D186', '#F2B5A7', '#C8A2C8', '#9AD0C2',
      '#E6B89C', '#A3C4F3', '#F4A6B8', '#B8E0D2', '#D9C2A3', '#A9B8E8'
    ]),
    new CourseColorPalette('macaron', '马卡龙', '清甜低饱和', [
      '#F7A8B8', '#A8D8EA', '#FFE0A3', '#B8E2C8', '#D8B4E2', '#FFC6A8',
      '#A9D6E5', '#F4C2C2', '#C7E9B0', '#E4C1F9', '#FFDAC1', '#B5EAD7'
    ]),
    new CourseColorPalette('salt', '盐系', '清冷低饱和', [
      '#A9C0C9', '#D9D2C7', '#B8C4B8', '#C7D3D4', '#A3B5B8', '#E3DDD3',
      '#9FB5A8', '#BFC8C2', '#D5CCBF', '#AAB8C2', '#C9D6CF', '#B4C7C9'
    ]),
    new CourseColorPalette('vintage', '复古', '低饱和复古', [
      '#C08552', '#8A6552', '#6B8E7B', '#B5A48C', '#7D6B7D', '#A65B4B',
      '#4F6D7A', '#C9A66B', '#6E7F5C', '#9C6B58', '#B49A72', '#7A8B8C'
    ]),
    new CourseColorPalette('sunny', '暖阳', '暖调柔光', [
      '#F2C28F', '#E8A87C', '#F4D6A0', '#D98E73', '#F0B7A4', '#E6C79C',
      '#F7D9B8', '#D4A373', '#EFC3A4', '#E9B384', '#F3D2B3', '#DDB892'
    ]),
    new CourseColorPalette('mint', '青提', '清新绿调', [
      '#B8E0B8', '#D4E8B0', '#A8D5BA', '#C9E4C5', '#B5D99C', '#D9E8B5',
      '#A3D9A5', '#C7E9B0', '#BEE3C4', '#D6E8C8', '#A9D6B5', '#CBE3B0'
    ])
  ];

  static get(id: string): CourseColorPalette {
    for (let i = 0; i < CourseColorPalettes.LIST.length; i++) {
      if (CourseColorPalettes.LIST[i].id === id) {
        return CourseColorPalettes.LIST[i];
      }
    }
    return CourseColorPalettes.LIST[0];
  }
}
