/**
 * 导入完成后按学期开始时间设置当前周。
 *
 * 仅在拿到有效开学周一时修改周次；写入 preferences 后同时更新 AppStore，
 * 不直接刷新小组件，交给后续 switchTable 的 bump 统一推送。
 */
import { AppState } from '../../app/AppState';
import { LegacyConfig } from '../../common/Constants';
import { WeekUtil } from '../../data/WeekUtil';
import { SemesterStartResolver } from './SemesterStartResolver';

export class ImportWeekApplier {
  static async apply(tableData: string): Promise<void> {
    const startMonday: string = await SemesterStartResolver.resolve(tableData);
    if (startMonday === '') {
      return;
    }
    let week: number = await WeekUtil.getWeekFromSemesterStart(startMonday);
    if (week < 1) {
      week = 1;
    } else if (week > LegacyConfig.MAX_WEEKS) {
      week = LegacyConfig.MAX_WEEKS;
    }
    await WeekUtil.setNowWeek(week);
    AppState.setCurrentWeekLocal(week);
  }
}
