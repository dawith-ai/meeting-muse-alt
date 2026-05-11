#!/usr/bin/env python3
"""
Pyannote segmentation 모델 → CoreML 변환 스크립트.

사용법:
    python3 scripts/convert_pyannote.py \\
        --output ~/Library/Application\\ Support/MeetingMuseAlt/Models/

요구사항:
    pip install coremltools pyannote.audio torch huggingface_hub

Hugging Face에서 pyannote/segmentation-3.0 모델을 사용하려면 토큰 필요:
    export HF_TOKEN=hf_xxxx
    huggingface-cli login

변환 결과:
    {output_dir}/pyannote-segmentation-3.0.mlpackage

스크립트를 실행한 뒤 MeetingMuseAlt 앱을 재시작하면 `PyannoteEngine`이
이 모델을 자동으로 발견하여 화자분리 추론을 수행한다.

※ M3 단계 산출물 — Swift CLI 환경에서 자동화하기 어려운 외부 자산 변환을
위한 사용자용 스크립트.
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Pyannote → CoreML 변환기")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path.home()
        / "Library/Application Support/MeetingMuseAlt/Models/",
        help="변환된 .mlpackage 출력 디렉토리",
    )
    parser.add_argument(
        "--model",
        default="pyannote/segmentation-3.0",
        help="HuggingFace 모델 식별자",
    )
    parser.add_argument(
        "--token",
        default=os.environ.get("HF_TOKEN"),
        help="HuggingFace API 토큰 (또는 HF_TOKEN 환경변수)",
    )
    args = parser.parse_args()

    try:
        import torch
        from pyannote.audio import Model
        import coremltools as ct
    except ImportError as e:
        print(
            "[error] 필요한 패키지가 설치되어 있지 않습니다:",
            e,
            file=sys.stderr,
        )
        print(
            "→ pip install coremltools pyannote.audio torch huggingface_hub",
            file=sys.stderr,
        )
        return 1

    args.output.mkdir(parents=True, exist_ok=True)
    print(f"[info] HuggingFace에서 모델 다운로드: {args.model}")
    try:
        model = Model.from_pretrained(args.model, use_auth_token=args.token)
    except Exception as e:
        print(f"[error] 모델 다운로드 실패: {e}", file=sys.stderr)
        print(
            "→ Hugging Face 토큰이 필요할 수 있습니다 (https://hf.co/settings/tokens).",
            file=sys.stderr,
        )
        return 2

    model.eval()
    # pyannote segmentation: 입력 (1, 1, samples@16kHz, T), 출력 (1, frames, 7)
    # 10초 윈도우 → 160000 샘플
    example = torch.randn(1, 1, 160_000)
    try:
        traced = torch.jit.trace(model, example)
    except Exception as e:
        print(f"[error] TorchScript 트레이싱 실패: {e}", file=sys.stderr)
        return 3

    print("[info] CoreML 변환 중...")
    try:
        mlmodel = ct.convert(
            traced,
            inputs=[
                ct.TensorType(
                    name="audio",
                    shape=(1, 1, 160_000),
                    dtype="float32",
                )
            ],
            compute_units=ct.ComputeUnit.ALL,
        )
    except Exception as e:
        print(f"[error] CoreML 변환 실패: {e}", file=sys.stderr)
        return 4

    out_path = args.output / "pyannote-segmentation-3.0.mlpackage"
    mlmodel.save(str(out_path))
    print(f"[ok] 저장 완료: {out_path}")
    print(
        "→ MeetingMuseAlt 앱을 재시작하면 PyannoteEngine 이 자동으로 이 모델을 사용합니다."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
