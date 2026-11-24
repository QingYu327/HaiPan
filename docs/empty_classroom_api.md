# 空教室查询接口（广东海洋大学 正方教务）

> 抓包时间：2026-08-31；已登录会话（学生 2024********）内置/外部浏览器实测。
> 用途：App「空教室」功能接入依据。

## 页面
- 入口 URL：`https://jw.gdou.edu.cn/cdjy/cdjy_cxKxcdlb.html?gnmkdm=N2155&layout=default`
- 查询接口：`POST https://jw.gdou.edu.cn/cdjy/cdjy_cxKxcdlb.html?doType=query&gnmkdm=N2155`

## 请求参数（application/x-www-form-urlencoded，POST body）
| 参数 | 说明 | 实测值 |
|---|---|---|
| `xqh_id` | 校区 id | `1`（湖光） |
| `xnm` | 学年 | `2026` |
| `xqm` | 学期 | `3` |
| `cdlb_id` | 场地类别 | `01`（多媒体教室） |
| `cdejlb_id` | 二级类别 | 空 |
| `qszws` | 座位下限 | 空 |
| `jszws` | 座位上限 | 空 |
| `cdmc` | 场地名称 | 空 |
| `lh` | 楼号 | 空 |
| `jyfs` | 借用方式 | `0` |
| `cdjylx` | 场地借用类型 | 空 |
| `sfbhkc` | 是否不缓冲考 | 空 |
| `zcd` | 周次 | `1` |
| `xqj` | 星期（逗号分隔） | `1,2,3` |
| `jcd` | 节次（单个） | `7` |
| `_search` | | `false` |
| `nd` | 时间戳 | `1788186649566` |
| `queryModel.showCount` | 每页 | `15` |
| `queryModel.currentPage` | 页码 | `1` |
| `queryModel.sortName` | 排序字段 | `cdbh ` |
| `queryModel.sortOrder` | 排序 | `asc` |
| `time` | | `0` |

> 关键条件：需至少给出 校区(xqh_id)+类别(cdlb_id)，并给出 周次(zcd)/星期(xqj)/节次(jcd) 才返回教室列表；只传 xnm+xqm 会返回 `"1"`（提示请选择筛选条件）。
> 会话：沿用登录 Cookie；建议复用时带上 `csrftoken`（登录页下发），可放入请求头/隐藏字段。

## 响应 JSON（jqGrid 风格）
```json
{
  "currentPage": 1,
  "items": [
    {
      "cd_id": "01001",
      "cdbh": "01001",
      "cdlb_id": "01",
      "cdlbmc": "多媒体教室",
      "cdmc": "广学楼多功能厅",
      "cdxqxx_id": "45F8BF2EF83A3FB0E063778926D2C290",
      "jxlmc": "广学楼",
      "lh": "18",
      "xqh_id": "1",
      "xqmc": "湖光校区",
      "zws": "400",
      "bz": "",
      "sfkjy": "否",
      "row_id": "1",
      "totalResult": "31"
    }
  ],
  "totalResult": "31"
}
```

### 字段说明（App 展示用）
| 字段 | 含义 |
|---|---|
| `cdmc` | 教室名称，如 广学楼502(多) |
| `cdbh` | 场地编号 |
| `cdlbmc` | 场地类别（多媒体教室等） |
| `jxlmc` | 教学楼名（广学楼） |
| `zws` | 座位数 |
| `xqmc` / `xqh_id` | 校区（湖光校区 / 1） |
| `bz` | 备注（如 研究生院使用的教室） |
| `sfkjy` | 是否可借 |
| `totalResult` | 总数（供分页） |

## 分页
- 改 `queryModel.currentPage`（1 起）与 `queryModel.showCount`。
- 排序 `queryModel.sortName=cdbh `（带尾空格）。

## 备注
- 星期/节次由页面 `th.selectTH`（jQuery UI selectable，选中加 `ui-selected`）读取，请求以 `xqj=逗号分隔`、`jcd=单个节次`提交。
- 若多节次查询，`jcd` 可能用 `1,2`；后续联调时以真实组合校验。