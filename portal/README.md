# 原型门户派生产物

本目录不维护独立的 HTML 版式。主站统一复用
[sanchuang-dev/base-prototype](https://github.com/sanchuang-dev/base-prototype)
的 `portal/index.html` + `demos.json`，由
`scripts/build-lab-portal.sh` 取冻结的上游提交、运行其
`scripts/render_portal.py`，输出临时部署产物。

只替换已上线的四个 `*.proto.3cgroup.cn` 入口及原来依赖 lab 路径的两个相对跳转。
任何首页视觉调整应优先在 `base-prototype` 修改，并评审后升级固定提交。
原型本身继续由产品仓库维护，本站仅引用入口。
