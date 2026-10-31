/**
 * 历史本地法律文档渲染组件；当前应用展示 AGC 托管隐私声明，本组件仅保留代码。
 *
 * 只做静态展示，不联网、不收集信息。
 */
import { Colors, FontSize, Spacing } from '../../../common/design/Tokens';
import { AppCard } from '../../../common/ui/AppCard';
import { LegalDocument, LegalSection } from './LegalDocuments';

@ComponentV2
export struct LegalDocumentView {
  @Require @Param doc: LegalDocument;

  build() {
    Column({ space: Spacing.Lg }) {
      AppCard() {
        Column({ space: Spacing.Sm }) {
          Text(`${this.doc.version}　生效日期：${this.doc.effectiveDate}`)
            .fontSize(FontSize.Caption)
            .fontColor(Colors.TextTertiary)
            .width('100%')
          ForEach(this.doc.intro, (paragraph: string) => {
            Text(paragraph)
              .fontSize(FontSize.BodySm)
              .fontColor(Colors.TextSecondary)
              .lineHeight(21)
              .width('100%')
          }, (paragraph: string, index: number) => `${this.doc.title}-intro-${index}`)
        }
        .alignItems(HorizontalAlign.Start)
      }

      ForEach(this.doc.sections, (section: LegalSection) => {
        AppCard() {
          Column({ space: Spacing.Sm }) {
            Text(section.heading)
              .fontSize(FontSize.Title)
              .fontWeight(FontWeight.Medium)
              .fontColor(Colors.TextPrimary)
              .width('100%')
            ForEach(section.paragraphs, (paragraph: string) => {
              Text(paragraph)
                .fontSize(FontSize.BodySm)
                .fontColor(Colors.TextSecondary)
                .lineHeight(21)
                .width('100%')
            }, (paragraph: string, index: number) => `${section.heading}-p-${index}`)
          }
          .alignItems(HorizontalAlign.Start)
        }
      }, (section: LegalSection) => section.heading)
    }
    .width('100%')
  }
}
