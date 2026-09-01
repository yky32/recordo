# tdParkId coverage

Vacancy join: handwritten `parks.td_park_id` first, then unique name, then 80m grid. **Never persist 80m.**

Live count 2026-08-31: **9 / 3367**.

| park | tdParkId |
|------|----------|
| 利園一期 `osm:node/1012176411` | `tdc1p1` |
| 利園二期 `osm:node/1012176498` | `tdc1p2` |
| 利園三期 `osm:node/8449215650` | `tdc1p5` |
| 希慎廣場 `osm:node/1966250272` | `tdc1p4` |
| 合和中心 `osm:relation/19035487` | `tdc5p1` |
| 圓方 `osm:way/1415166825` | `tdc8p10` |
| 香港站 `osm:node/1616458976` | `tdc8p3` |
| 九龍站 `osm:node/12923224401` | `tdc8p2` |
| 錦上路 `osm:node/12293910833` | `tdc8p15` |

**No TD lot (do not invent):** 海港城四場、時代廣場、K11 Art / MUSEA、V Walk、ifc.

Empty `tdParkId` → 80m only inside the nearby window. Wrong-lot steal still possible outside these 9.
