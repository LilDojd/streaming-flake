def upsert_template_sources:
  reduce $template[0].sources[] as $source (
    .;
    if any(.sources[]; .uuid == $source.uuid) then . else .sources += [$source] end
  );

def upsert_template_scene_order:
  reduce $template[0].scene_order[] as $scene (
    .;
    if any(.scene_order[]; .name == $scene.name) then . else .scene_order += [$scene] end
  );

def remove_source($name):
  .sources |= map(select(.name != $name));

def remove_scene($name):
  remove_source($name) |
  .scene_order |= map(select(.name != $name));

def remove_overlay_item($uuid):
  (.sources[] | select(.name == "[Component] Stream Overlay") | .settings.items) |=
    map(select(.source_uuid != $uuid));

def upsert_overlay_item($uuid):
  ($template[0].sources[] | select(.name == "[Component] Stream Overlay") |
    .settings.items[] | select(.source_uuid == $uuid)) as $item |
  if any(
    .sources[] | select(.name == "[Component] Stream Overlay") | .settings.items[];
    .source_uuid == $uuid
  ) then
    .
  else
    (.sources[] | select(.name == "[Component] Stream Overlay") | .settings.items) += [ $item ]
  end;

def reconcile_filters($existing; $managed; $enabled):
  ($existing // []) as $current |
  if $enabled then
    reduce $managed[] as $filter (
      $current;
      if any(.[]; .uuid == $filter.uuid) then
        map(if .uuid == $filter.uuid then $filter else . end)
      else
        . + [ $filter ]
      end
    )
  else
    [ $current[] | select(.uuid as $uuid | all($managed[]; .uuid != $uuid)) ]
  end;

def managed_scene_names:
  [
    "Starting Soon",
    "Programming",
    "Second Monitor",
    "BRB",
    "Privacy",
    "[Component] Primary Monitor",
    "[Component] Secondary Monitor",
    "[Component] Stream Overlay"
  ];

def upsert_template_scene_items:
  reduce managed_scene_names[] as $name (
    .;
    ($template[0].sources[] | select(.name == $name)) as $managed |
    reduce $managed.settings.items[] as $item (
      .;
      if any(
        .sources[] | select(.uuid == $managed.uuid) | .settings.items[];
        .source_uuid == $item.source_uuid
      ) then
        .
      else
        (.sources[] | select(.uuid == $managed.uuid) | .settings.items) += [ $item ]
      end
    )
  );

upsert_template_sources |
upsert_template_scene_order |
upsert_template_scene_items |

if ((.modules["streaming-flake"].version // 0) < 3) then
  (.sources[] | select(.uuid == "77777777-7777-4777-8777-777777777777") | .settings.items) |=
    map(select(
      .source_uuid != "33333333-3333-4333-8333-333333333333" and
      .source_uuid != "99999999-9999-4999-8999-999999999999"
    )) |
  .modules["streaming-flake"].version = 3
else
  .
end |

.name = $collectionName |
(.sources[] | select(.uuid == "33333333-3333-4333-8333-333333333333") | .name) =
  "Primary Monitor Capture" |
(.sources[] | select(.id == "pipewire-screen-capture-source") | .settings.ShowCursor) = $showCursor |
(.sources[] | select(.uuid == "33333333-3333-4333-8333-333333333333") | .settings.RestoreToken) =
  $primaryRestoreToken |
(.sources[] | select(.uuid == "cccccccc-cccc-4ccc-8ccc-cccccccccccc") | .settings.RestoreToken) =
  $secondaryRestoreToken |
(.sources[] | select(.name == "Synthwave Terrain") | .settings) |=
  (.local_file = $synthwaveShader |
    .width = $shaderWidth |
    .height = $shaderHeight |
    .fps = $shaderFps |
    .shutdown = true |
    .restart_when_active = false) |
(.sources[] | select(.name == "Cosmic Strings") | .settings) |=
  (.local_file = $cosmicShader |
    .width = $shaderWidth |
    .height = $shaderHeight |
    .fps = $shaderFps |
    .shutdown = true |
    .restart_when_active = false) |
(.sources[] | select(.name == "Privacy Background") | .settings) |=
  (.width = $width | .height = $height) |
(.sources[] | select(.name == "Intermission Text Backplate") | .settings) |=
  (.width = (1200 * $width / 2560) | .height = (240 * $height / 1440)) |
(.sources[] | select(.name == "Twitch Chat") | .settings) |=
  (.width = (520 * $width / 2560) | .height = (620 * $height / 1440)) |
(.sources[] | select(.name == "Stream Alerts") | .settings) |=
  (.width = (520 * $width / 2560) | .height = (300 * $height / 1440)) |
(.sources[] | select(.name == "Live Captions") | .settings.custom_width) =
  (1600 * $width / 2560) |
(.sources[] | select(.name == "Keystroke Display") | .settings.custom_width) =
  (600 * $width / 2560) |
(.sources[] | select(.name == "Privacy Text") | .settings.text) = $privacyText |

reduce managed_scene_names[] as $name (
  .;
  ($template[0].sources[] | select(.name == $name)) as $managed |
  reduce $managed.settings.items[] as $item (
    .;
    (if $item.pos? then
      (.sources[] | select(.uuid == $managed.uuid) | .settings.items[] |
        select(.source_uuid == $item.source_uuid) | .pos) = {
          x: ($item.pos.x * $width / 2560),
          y: ($item.pos.y * $height / 1440)
        }
    else
      .
    end) |
    (.sources[] | select(.uuid == $managed.uuid) | .settings.items[] |
      select(.source_uuid == $item.source_uuid and .bounds_type? == 2) | .bounds) =
      (if $item.source_uuid == "cccccccc-cccc-4ccc-8ccc-cccccccccccc" then
        { x: $height, y: $width }
      else
        { x: $width, y: $height }
      end)
  )
) |

(.sources[] | select(.name == "[Component] Secondary Monitor") | .settings.items[] |
  select(.source_uuid == "cccccccc-cccc-4ccc-8ccc-cccccccccccc")) |=
  (del(.pos_rel, .scale_rel, .bounds_rel, .scale_ref) |
    .align = 0 |
    .rot = 90 |
    .bounds_align = 0 |
    .bounds_type = 2 |
    .pos = { x: ($width / 2), y: ($height / 2) } |
    .bounds = { x: $height, y: $width }) |

if $chatEnabled then
  upsert_overlay_item("99999999-9999-4999-8999-999999999999") |
  (.sources[] | select(.name == "Twitch Chat") | .settings) |=
    (.url = $chatUrl | .css = $chatCss)
else
  remove_source("Twitch Chat") |
  remove_overlay_item("99999999-9999-4999-8999-999999999999")
end |

if $alertsEnabled then
  upsert_overlay_item("12121212-1212-4212-8212-121212121212") |
  (.sources[] | select(.name == "Stream Alerts") | .settings.url) =
    ($alertsUrl | sub("\\r?\\n$"; ""))
else
  remove_source("Stream Alerts") |
  remove_overlay_item("12121212-1212-4212-8212-121212121212")
end |

if $captionsEnabled then
  upsert_overlay_item("13131313-1313-4313-8313-131313131313") |
  (.sources[] | select(.name == "Live Captions") | .settings.text_file) = $captionsFile
else
  remove_source("Live Captions") |
  remove_overlay_item("13131313-1313-4313-8313-131313131313")
end |

if $keystrokesEnabled then
  upsert_overlay_item("17171717-1717-4717-8717-171717171717")
else
  remove_source("Keystroke Display") |
  remove_overlay_item("17171717-1717-4717-8717-171717171717")
end |

if $secondMonitorEnabled then
  .
else
  remove_source("Secondary Monitor Capture") |
  remove_scene("[Component] Secondary Monitor") |
  remove_scene("Second Monitor")
end |

if $privacyEnabled then
  .
else
  remove_source("Privacy Background") |
  remove_source("Privacy Text") |
  remove_scene("Privacy")
end |

.AuxAudioDevice1.filters = reconcile_filters(
  .AuxAudioDevice1.filters;
  $micFilters;
  $micFiltersEnabled
) |

(.sources[] | select(.name == "[Component] Primary Monitor") | .filters) = reconcile_filters(
  (.sources[] | select(.name == "[Component] Primary Monitor") | .filters);
  [ $cleanRecordingFilter ];
  $cleanRecordingEnabled
)
