/**
 * 设备形态判断。
 *
 * 只用于区分交互方式，不用来推断屏幕尺寸；布局断点统一走 design/Breakpoints。
 */
import { deviceInfo } from '@kit.BasicServicesKit';

/** 当前设备是否为 PC / 2in1：上下文菜单使用鼠标右键，而不是触屏长按。 */
export const IS_2IN1: boolean = deviceInfo.deviceType === '2in1';
