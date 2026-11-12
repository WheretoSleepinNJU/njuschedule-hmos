/**
 * 课程组删除流程：列表/详情/课表长按共用。
 *
 * 同一门课在数据库里是多行（多个时段），删除入口必须先按数据层规则加载整组，
 * 否则会只删掉其中一个时段，和编辑页的“整组删除”语义不一致。
 */
import { UIContext } from '@kit.ArkUI';
import { Feedback } from '../../common/ui/Feedback';
import { AppState } from '../../app/AppState';
import { CourseRepository } from '../../data/CourseRepository';
import { Course } from '../../data/models/Models';

export class CourseDeleteFlow {
  /**
   * 显示整组删除确认，确认后事务删除并刷新全局数据。
   * 加载/删除失败走 onError，不显示误导性的成功状态。
   */
  static async confirmDelete(ctx: UIContext, course: Course,
    onDeleted: () => void, onError: () => void): Promise<void> {
    try {
      const meetings: Course[] = await CourseRepository.getMeetings(course);
      if (meetings.length === 0) {
        onError();
        return;
      }
      Feedback.confirmDanger(ctx, '删除课程',
        `确定删除「${course.name}」的全部 ${meetings.length} 个时段吗？删除后不可恢复。`, '删除', () => {
          AppState.deleteCourseGroup(meetings)
            .then((deleted: boolean) => {
              if (deleted) {
                onDeleted();
              } else {
                onError();
              }
            })
            .catch(() => {
              onError();
            });
        });
    } catch (err) {
      onError();
    }
  }
}
