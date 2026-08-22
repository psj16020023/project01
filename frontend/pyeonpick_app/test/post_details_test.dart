import 'package:flutter_test/flutter_test.dart';
import 'package:pyeonpick_app/src/models/post.dart';

void main() {
  test('사용한 상품 목록을 게시글 상세 JSON에 보존한다', () {
    const details = PostDetails(
      usedProducts: <String>['불닭볶음면', '스트링치즈'],
      eatingSteps: <String>['함께 데운다'],
      tips: <String>[],
      cautions: <String>[],
      situationTags: <String>[],
      reviewPoints: <String>[],
      prepTimeTag: '',
    );

    final restored = PostDetails.fromJson(details.toJson());

    expect(restored.usedProducts, <String>['불닭볶음면', '스트링치즈']);
    expect(restored.eatingSteps, <String>['함께 데운다']);
  });
}
