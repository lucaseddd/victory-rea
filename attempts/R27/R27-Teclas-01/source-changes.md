# R27 · keyboard, mouse and PC key prompts · source changes

Base: the R27-Atual build (VI-BR-PORT `2954325` + [R27-Atual-01's diff](../R27-Atual-01/source-changes.md)). Apply after that one. Includes an adaptation of Marvisak/VIctory#3433 (key caps over the title's button pictures, by @imjustprism) and the window caption change. Only VIctory source (open source); nothing from the title.

```diff
diff -ruN -x target -x Cargo.lock -x '*.rej' -x .git a/crates/victory-core/src/lib.rs b/crates/victory-core/src/lib.rs
--- a/crates/victory-core/src/lib.rs	2026-11-27 11:51:28.367891300 -0300
+++ b/crates/victory-core/src/lib.rs	2026-11-27 19:10:51.331064600 -0300
@@ -4,9 +4,11 @@
 //! * [`policy`]: the runtime half of rule #1, refusing to write
 //!   game-derived data into the source tree.
 //! * [`logging`]: one tracing setup for all binaries.
+//! * [`pad`]: the keys of the keyboard's stand-in gamepad.
 
 pub mod config;
 pub mod logging;
+pub mod pad;
 pub mod policy;
 
 pub use config::Config;
diff -ruN -x target -x Cargo.lock -x '*.rej' -x .git a/crates/victory-core/src/pad.rs b/crates/victory-core/src/pad.rs
--- a/crates/victory-core/src/pad.rs	1969-12-31 21:00:00.000000000 -0300
+++ b/crates/victory-core/src/pad.rs	2026-11-27 19:11:28.507587200 -0300
@@ -0,0 +1,166 @@
+//! The keyboard's stand-in gamepad: which key drives each gamepad control.
+//!
+//! Input reads the keys through it, and anything that shows a control to
+//! the player names the key from it, so both agree. It knows nothing of
+//! readings or devices.
+
+/// The Windows virtual key of Backspace.
+pub const VK_BACK: u8 = 0x08;
+/// The Windows virtual key of Tab.
+pub const VK_TAB: u8 = 0x09;
+/// The Windows virtual key of Enter.
+pub const VK_RETURN: u8 = 0x0D;
+/// The Windows virtual key of Esc.
+pub const VK_ESCAPE: u8 = 0x1B;
+/// The Windows virtual key of the left arrow.
+pub const VK_LEFT: u8 = 0x25;
+/// The Windows virtual key of the up arrow.
+pub const VK_UP: u8 = 0x26;
+/// The Windows virtual key of the right arrow.
+pub const VK_RIGHT: u8 = 0x27;
+/// The Windows virtual key of the down arrow.
+pub const VK_DOWN: u8 = 0x28;
+
+/// Declares the gamepad's controls and the list of all of them from one
+/// list, so that the list cannot miss a control.
+macro_rules! pad_controls {
+    ($($control:ident),* $(,)?) => {
+        /// A control of a gamepad.
+        #[derive(Clone, Copy, Debug, PartialEq, Eq)]
+        pub enum PadControl {
+            $($control),*
+        }
+
+        impl PadControl {
+            /// Every control, in the order declared.
+            pub const ALL: &[Self] = &[$(Self::$control),*];
+        }
+    };
+}
+
+pad_controls!(
+    Menu,
+    View,
+    A,
+    B,
+    X,
+    Y,
+    Up,
+    Down,
+    Left,
+    Right,
+    LeftShoulder,
+    RightShoulder,
+    LeftStick,
+    RightStick,
+    LeftTrigger,
+    RightTrigger,
+    LeftStickUp,
+    LeftStickDown,
+    LeftStickLeft,
+    LeftStickRight,
+    RightStickUp,
+    RightStickDown,
+    RightStickLeft,
+    RightStickRight,
+);
+
+/// The virtual key that drives `control` on the keyboard's stand-in gamepad;
+/// README lists them.
+#[must_use]
+pub const fn fallback_key(control: PadControl) -> u8 {
+    match control {
+        PadControl::Menu => VK_ESCAPE,
+        PadControl::View => VK_TAB,
+        PadControl::A => VK_RETURN,
+        PadControl::B => VK_BACK,
+        PadControl::X => b'X',
+        PadControl::Y => b'Y',
+        PadControl::Up => VK_UP,
+        PadControl::Down => VK_DOWN,
+        PadControl::Left => VK_LEFT,
+        PadControl::Right => VK_RIGHT,
+        PadControl::LeftShoulder => b'Q',
+        PadControl::RightShoulder => b'E',
+        PadControl::LeftStick => b'F',
+        PadControl::RightStick => b'H',
+        PadControl::LeftTrigger => b'Z',
+        PadControl::RightTrigger => b'C',
+        PadControl::LeftStickUp => b'W',
+        PadControl::LeftStickDown => b'S',
+        PadControl::LeftStickLeft => b'A',
+        PadControl::LeftStickRight => b'D',
+        PadControl::RightStickUp => b'I',
+        PadControl::RightStickDown => b'K',
+        PadControl::RightStickLeft => b'J',
+        PadControl::RightStickRight => b'L',
+    }
+}
+
+/// The Windows virtual key of the left mouse button.
+pub const VK_LBUTTON: u8 = 0x01;
+/// The Windows virtual key of the right mouse button.
+pub const VK_RBUTTON: u8 = 0x02;
+/// The Windows virtual key of the space bar.
+pub const VK_SPACE: u8 = 0x20;
+/// The Windows virtual key of the left Ctrl.
+pub const VK_LCONTROL: u8 = 0xA2;
+
+/// The key (or mouse button) that drives `control` in the GTA V PC-style
+/// layout (`VICTORY_KBM_GTA=1`, `gameinput.rs` `GTA_BUTTONS`): the first key
+/// of each control there, as a prompt shows it.
+#[must_use]
+pub const fn gta_key(control: PadControl) -> u8 {
+    match control {
+        PadControl::Menu => VK_ESCAPE,
+        PadControl::View => b'V',
+        PadControl::A => VK_RETURN,
+        PadControl::B => VK_BACK,
+        PadControl::X => VK_SPACE,
+        PadControl::Y => b'F',
+        PadControl::Up => VK_UP,
+        PadControl::Down => VK_DOWN,
+        PadControl::Left => VK_LEFT,
+        PadControl::Right => b'E',
+        PadControl::LeftShoulder => VK_TAB,
+        PadControl::RightShoulder => b'Q',
+        PadControl::LeftStick => VK_LCONTROL,
+        PadControl::RightStick => b'C',
+        PadControl::LeftTrigger => VK_RBUTTON,
+        PadControl::RightTrigger => VK_LBUTTON,
+        PadControl::LeftStickUp => b'W',
+        PadControl::LeftStickDown => b'S',
+        PadControl::LeftStickLeft => b'A',
+        PadControl::LeftStickRight => b'D',
+        PadControl::RightStickUp => b'I',
+        PadControl::RightStickDown => b'K',
+        PadControl::RightStickLeft => b'J',
+        PadControl::RightStickRight => b'L',
+    }
+}
+
+/// The key a prompt shows for `control`: the GTA layout's with
+/// `VICTORY_KBM_GTA` on (`1`, `true`, `yes`, `on`), else [`fallback_key`].
+#[must_use]
+pub fn shown_key(control: PadControl) -> u8 {
+    static GTA: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
+    let gta = *GTA.get_or_init(|| {
+        std::env::var("VICTORY_KBM_GTA")
+            .is_ok_and(|v| matches!(v.trim().to_ascii_lowercase().as_str(), "1" | "true" | "yes" | "on"))
+    });
+    if gta { gta_key(control) } else { fallback_key(control) }
+}
+
+#[cfg(test)]
+mod tests {
+    use super::{PadControl, fallback_key};
+
+    #[test]
+    fn every_control_has_a_key_of_its_own() {
+        let mut keys: Vec<u8> = PadControl::ALL.iter().map(|&c| fallback_key(c)).collect();
+        keys.sort_unstable();
+        keys.dedup();
+
+        assert_eq!(keys.len(), 24);
+    }
+}
diff -ruN -x target -x Cargo.lock -x '*.rej' -x .git a/crates/victory-formats/src/gfx.rs b/crates/victory-formats/src/gfx.rs
--- a/crates/victory-formats/src/gfx.rs	1969-12-31 21:00:00.000000000 -0300
+++ b/crates/victory-formats/src/gfx.rs	2026-11-27 19:10:51.331564500 -0300
@@ -0,0 +1,941 @@
+//! Scaleform GFx movies: the `GFX` container around a SWF tag stream.
+//!
+//! Reads an uncompressed movie's shapes, sprites, placements and class
+//! names, writes solid vector shapes, and builds a copy of a movie with some
+//! of its shapes replaced. It does not read compressed (`CFX`) movies, and it
+//! does not interpret scripts, fonts, bitmaps or placement matrices.
+
+use std::collections::HashMap;
+use std::ops::Range;
+
+/// Tag codes of the SWF tag stream.
+const END: u16 = 0;
+const SHOW_FRAME: u16 = 1;
+const PLACE_OBJECT: u16 = 4;
+const REMOVE_OBJECT: u16 = 5;
+const DEFINE_BUTTON: u16 = 7;
+const DEFINE_BUTTON_2: u16 = 34;
+const PLACE_OBJECT_2: u16 = 26;
+const REMOVE_OBJECT_2: u16 = 28;
+const DEFINE_SHAPE_3: u16 = 32;
+const DEFINE_SPRITE: u16 = 39;
+const PLACE_OBJECT_3: u16 = 70;
+const SYMBOL_CLASS: u16 = 76;
+
+/// A tag header's length field when the real length follows as a `u32`.
+const LONG_TAG: u16 = 0x3F;
+/// `PlaceObject2` flags: the placement changes the character at its depth,
+/// and it names a character.
+const PLACE_MOVES: u8 = 1;
+const PLACE_NAMES_CHARACTER: u8 = 2;
+/// A `PlaceObject2` flag: the placed character is a mask over deeper ones.
+const PLACE_CLIPS: u8 = 0x40;
+/// Style change flags of a shape record.
+const MOVE_TO: u32 = 0b00001;
+const FILL_STYLE_0: u32 = 0b00010;
+/// The bytes of a movie's header: `GFX`, a version and the movie's length.
+pub const HEADER_BYTES: usize = 8;
+/// The widest signed field a shape's bounds or a move can have, bits.
+const WIDEST_FIELD_BITS: u32 = 31;
+/// The widest signed delta an edge can have, bits (a 4-bit count plus 2).
+const WIDEST_EDGE_BITS: u32 = 17;
+
+/// A position in twips (a twentieth of a pixel), y down.
+#[derive(Clone, Copy, Debug, PartialEq, Eq)]
+pub struct Point {
+    pub x: i32,
+    pub y: i32,
+}
+
+/// One edge of a contour, from where the previous one ended, in points of
+/// some kind `P` (twips for a shape).
+#[derive(Clone, Copy, Debug, PartialEq, Eq)]
+pub enum Edge<P = Point> {
+    Line(P),
+    /// A quadratic curve.
+    Curve {
+        control: P,
+        to: P,
+    },
+}
+
+impl<P: Copy> Edge<P> {
+    /// The edge's control and end; a line's control is its end.
+    pub fn points(self) -> [P; 2] {
+        match self {
+            Self::Line(to) => [to, to],
+            Self::Curve { control, to } => [control, to],
+        }
+    }
+
+    /// The same edge with every point moved by `place`.
+    pub fn map<Q>(self, place: impl Fn(P) -> Q) -> Edge<Q> {
+        match self {
+            Self::Line(to) => Edge::Line(place(to)),
+            Self::Curve { control, to } => Edge::Curve {
+                control: place(control),
+                to: place(to),
+            },
+        }
+    }
+}
+
+/// One closed outline, in points of some kind `P` (twips for a shape).
+#[derive(Clone, Debug, PartialEq, Eq)]
+pub struct Contour<P = Point> {
+    pub start: P,
+    pub edges: Vec<Edge<P>>,
+}
+
+impl<P: Copy> Contour<P> {
+    /// Its start, then each edge's control and end.
+    pub fn points(&self) -> impl Iterator<Item = P> + '_ {
+        std::iter::once(self.start).chain(self.edges.iter().flat_map(|edge| edge.points()))
+    }
+
+    /// The same outline with every point moved by `place`.
+    pub fn map<Q>(&self, place: impl Fn(P) -> Q) -> Contour<Q> {
+        Contour {
+            start: place(self.start),
+            edges: self.edges.iter().map(|edge| edge.map(&place)).collect(),
+        }
+    }
+
+    /// Whether its last edge ends where it starts.
+    fn closed(&self) -> bool
+    where
+        P: PartialEq,
+    {
+        self.edges
+            .last()
+            .is_some_and(|edge| edge.points()[1] == self.start)
+    }
+}
+
+/// The body of a `DefineShape3` tag, made by [`shape`]. It carries the id
+/// of the shape it defines.
+#[derive(Clone, Debug, PartialEq, Eq)]
+pub struct ShapeBody {
+    id: u16,
+    bytes: Vec<u8>,
+}
+
+/// What one placement tag does at its depth.
+#[derive(Clone, Copy, Debug, PartialEq, Eq)]
+pub enum Change {
+    /// A character placed at a free depth.
+    Place(u16),
+    /// A character placed at a free depth as a mask over deeper ones.
+    Mask(u16),
+    /// The character at the depth replaced by this one.
+    Replace(u16),
+    /// The character at the depth moved or recoloured.
+    Modify,
+    /// The character at the depth removed.
+    Remove,
+    /// A placement this module does not read (`PlaceObject3`).
+    Unread,
+}
+
+/// A depth of a timeline: deeper characters are drawn first.
+#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
+pub struct Depth(pub u16);
+
+/// One placement tag of a timeline.
+#[derive(Clone, Copy, Debug, PartialEq, Eq)]
+pub struct Placement {
+    /// The frame it is in, counted from 0.
+    pub frame: u16,
+    pub depth: Depth,
+    pub change: Change,
+}
+
+/// A sprite and its own timeline.
+#[derive(Clone, Debug, PartialEq, Eq)]
+pub struct Sprite {
+    pub id: u16,
+    pub placements: Vec<Placement>,
+}
+
+/// One tag of a tag stream: its code, where its header starts and its body.
+#[derive(Clone, Debug, PartialEq, Eq)]
+struct Tag {
+    code: u16,
+    start: usize,
+    body: Range<usize>,
+}
+
+fn u16_at(bytes: &[u8], at: usize) -> Option<u16> {
+    Some(u16::from_le_bytes(*bytes.get(at..)?.first_chunk()?))
+}
+
+fn u32_at(bytes: &[u8], at: usize) -> Option<u32> {
+    Some(u32::from_le_bytes(*bytes.get(at..)?.first_chunk()?))
+}
+
+/// The tags in `range` of `bytes`, up to and including the first end tag.
+/// `None` when a tag runs past the range.
+fn tags(bytes: &[u8], range: Range<usize>) -> Option<Vec<Tag>> {
+    let mut found = Vec::new();
+    let mut at = range.start;
+    while at < range.end {
+        let head = u16_at(bytes, at)?;
+        let code = head >> 6;
+        let (body, len) = match head & LONG_TAG {
+            LONG_TAG => (
+                at.checked_add(6)?,
+                usize::try_from(u32_at(bytes, at.checked_add(2)?)?).ok()?,
+            ),
+            short => (at.checked_add(2)?, usize::from(short)),
+        };
+        let end = body.checked_add(len).filter(|&end| end <= range.end)?;
+        found.push(Tag {
+            code,
+            start: at,
+            body: body..end,
+        });
+        if code == END {
+            break;
+        }
+        at = end;
+    }
+    Some(found)
+}
+
+/// The placements among `tags` of `bytes`, frame by frame. `None` when a
+/// placement's body is too short for its fields.
+fn placements(bytes: &[u8], tags: &[Tag]) -> Option<Vec<Placement>> {
+    let mut found = Vec::new();
+    let mut frame = 0u16;
+    for tag in tags {
+        let body = bytes.get(tag.body.clone())?;
+        let (depth, change) = match tag.code {
+            SHOW_FRAME => {
+                frame = frame.saturating_add(1);
+                continue;
+            }
+            // A character, then a depth.
+            PLACE_OBJECT => (u16_at(body, 2)?, Change::Place(u16_at(body, 0)?)),
+            // Flags, a depth, then the character when the flags name one.
+            PLACE_OBJECT_2 => {
+                let flags = *body.first()?;
+                let moves = flags & PLACE_MOVES != 0;
+                let change = match (moves, flags & PLACE_NAMES_CHARACTER != 0) {
+                    (false, true) if flags & PLACE_CLIPS != 0 => Change::Mask(u16_at(body, 3)?),
+                    (false, true) => Change::Place(u16_at(body, 3)?),
+                    (true, true) => Change::Replace(u16_at(body, 3)?),
+                    (_, false) => Change::Modify,
+                };
+                (u16_at(body, 1)?, change)
+            }
+            // Two bytes of flags, then a depth.
+            PLACE_OBJECT_3 => (u16_at(body, 2)?, Change::Unread),
+            // A character, then a depth; or the depth alone.
+            REMOVE_OBJECT => (u16_at(body, 2)?, Change::Remove),
+            REMOVE_OBJECT_2 => (u16_at(body, 0)?, Change::Remove),
+            _ => continue,
+        };
+        found.push(Placement {
+            frame,
+            depth: Depth(depth),
+            change,
+        });
+    }
+    Some(found)
+}
+
+/// Whether `header` starts an uncompressed movie `len` bytes long.
+#[must_use]
+pub fn names_movie(header: &[u8; HEADER_BYTES], len: usize) -> bool {
+    let [b'G', b'F', b'X', _, length @ ..] = *header else {
+        return false;
+    };
+    usize::try_from(u32::from_le_bytes(length)).is_ok_and(|length| length == len)
+}
+
+/// An uncompressed movie with its top-level tags listed.
+pub struct Movie<'a> {
+    bytes: &'a [u8],
+    /// Where the first tag starts, after the header.
+    first: usize,
+    tags: Vec<Tag>,
+    /// How many `DefineShape3` tags define each shape id.
+    shape_counts: HashMap<u16, usize>,
+}
+
+impl<'a> Movie<'a> {
+    /// Lists the tags of `bytes`. `None` when they are not an uncompressed
+    /// movie, the length in the header is not theirs, or a tag runs past
+    /// the end.
+    #[must_use]
+    pub fn parse(bytes: &'a [u8]) -> Option<Self> {
+        if !names_movie(bytes.first_chunk()?, bytes.len()) {
+            return None;
+        }
+        // The frame rectangle: a 5-bit field width, then four fields; the
+        // frame rate and the frame count follow it.
+        let field_bits = usize::from(bytes.get(8)? >> 3);
+        let first = 8 + (5 + 4 * field_bits).div_ceil(8) + 4;
+        let tags = tags(bytes, first..bytes.len())?;
+        let mut shape_counts = HashMap::new();
+        let shapes = tags.iter().filter(|tag| tag.code == DEFINE_SHAPE_3);
+        for id in shapes.filter_map(|tag| u16_at(bytes.get(tag.body.clone())?, 0)) {
+            *shape_counts.entry(id).or_insert(0) += 1;
+        }
+        Some(Self {
+            bytes,
+            first,
+            tags,
+            shape_counts,
+        })
+    }
+
+    fn bodies(&self, code: u16) -> impl Iterator<Item = &'a [u8]> {
+        let bytes = self.bytes;
+        self.tags
+            .iter()
+            .filter(move |tag| tag.code == code)
+            .filter_map(move |tag| bytes.get(tag.body.clone()))
+    }
+
+    /// How many `DefineShape3` tags define each shape id.
+    #[must_use]
+    pub fn shape_counts(&self) -> &HashMap<u16, usize> {
+        &self.shape_counts
+    }
+
+    /// Whether the movie defines buttons, whose records place characters
+    /// this module does not read.
+    #[must_use]
+    pub fn defines_buttons(&self) -> bool {
+        self.tags
+            .iter()
+            .any(|tag| matches!(tag.code, DEFINE_BUTTON | DEFINE_BUTTON_2))
+    }
+
+    /// The placements of the movie's own timeline. `None` when one is too
+    /// short for its fields.
+    #[must_use]
+    pub fn timeline(&self) -> Option<Vec<Placement>> {
+        placements(self.bytes, &self.tags)
+    }
+
+    /// The movie's sprites: an id, a frame count, then tags of their own.
+    /// `None` when a sprite's tags run past its body or a placement is too
+    /// short.
+    #[must_use]
+    pub fn sprites(&self) -> Option<Vec<Sprite>> {
+        self.bodies(DEFINE_SPRITE)
+            .map(|body| {
+                let own = tags(body, 4..body.len())?;
+                Some(Sprite {
+                    id: u16_at(body, 0)?,
+                    placements: placements(body, &own)?,
+                })
+            })
+            .collect()
+    }
+
+    /// The class name the movie gives each character it exports, without
+    /// its NUL: a count, then a character id and a name each. `None` when a
+    /// table is cut short.
+    #[must_use]
+    pub fn classes(&self) -> Option<Vec<(u16, &'a [u8])>> {
+        let mut found = Vec::new();
+        for body in self.bodies(SYMBOL_CLASS) {
+            let mut rest = body.get(2..)?;
+            for _ in 0..u16_at(body, 0)? {
+                let id = u16_at(rest, 0)?;
+                let named = rest.get(2..)?;
+                let end = named.iter().position(|&byte| byte == 0)?;
+                found.push((id, named.get(..end)?));
+                rest = named.get(end + 1..)?;
+            }
+        }
+        Some(found)
+    }
+
+    /// A copy of the movie in which each body replaces the shape it names,
+    /// and every other tag is as it was. `None` when two bodies name one
+    /// shape, or a body names no `DefineShape3` or more than one.
+    #[must_use]
+    pub fn replace_shapes(&self, bodies: &[ShapeBody]) -> Option<Vec<u8>> {
+        let counts = &self.shape_counts;
+        let mut by_id = HashMap::with_capacity(bodies.len());
+        for body in bodies {
+            if counts.get(&body.id) != Some(&1) || by_id.insert(body.id, body).is_some() {
+                return None;
+            }
+        }
+        let mut out = Vec::with_capacity(self.bytes.len());
+        out.extend(self.bytes.get(..self.first)?);
+        for tag in &self.tags {
+            let id = (tag.code == DEFINE_SHAPE_3)
+                .then(|| u16_at(self.bytes.get(tag.body.clone())?, 0))
+                .flatten();
+            match id.and_then(|id| by_id.get(&id)) {
+                Some(body) => {
+                    out.extend(((DEFINE_SHAPE_3 << 6) | LONG_TAG).to_le_bytes());
+                    out.extend(u32::try_from(body.bytes.len()).ok()?.to_le_bytes());
+                    out.extend(&body.bytes);
+                }
+                None => out.extend(self.bytes.get(tag.start..tag.body.end)?),
+            }
+        }
+        let len = u32::try_from(out.len()).ok()?.to_le_bytes();
+        out.get_mut(4..8)?.copy_from_slice(&len);
+        Some(out)
+    }
+}
+
+/// Bits written most significant first.
+struct Bits {
+    bytes: Vec<u8>,
+    /// Bits still free in the last byte.
+    free: u32,
+}
+
+impl Bits {
+    fn put(&mut self, value: u32, count: u32) {
+        for bit in (0..count).rev() {
+            if self.free == 0 {
+                self.bytes.push(0);
+                self.free = 8;
+            }
+            self.free -= 1;
+            if let Some(last) = self.bytes.last_mut() {
+                *last |= u8::from((value >> bit) & 1 == 1) << self.free;
+            }
+        }
+    }
+
+    fn signed(&mut self, value: i32, count: u32) {
+        self.put(value.cast_unsigned(), count);
+    }
+}
+
+/// The bits a signed field needs to hold every value.
+fn field_bits(values: &[i32]) -> u32 {
+    values
+        .iter()
+        .map(|&value| 33 - (value ^ (value >> 31)).leading_zeros())
+        .max()
+        .unwrap_or(1)
+}
+
+fn delta(from: Point, to: Point) -> Option<[i32; 2]> {
+    Some([to.x.checked_sub(from.x)?, to.y.checked_sub(from.y)?])
+}
+
+/// A `DefineShape3` body: `contours` filled with one solid colour, holes
+/// running the other way to the outer contours. Every edge carries the
+/// colour as fill style 0. `None` when a contour does not end where it
+/// starts, or a coordinate does not fit the record's fields.
+#[must_use]
+pub fn shape(id: u16, rgba: [u8; 4], contours: &[Contour]) -> Option<ShapeBody> {
+    if !contours.iter().all(Contour::closed) {
+        return None;
+    }
+    let points = || contours.iter().flat_map(Contour::points);
+    let bounds = [
+        points().map(|p| p.x).min().unwrap_or(0),
+        points().map(|p| p.x).max().unwrap_or(0),
+        points().map(|p| p.y).min().unwrap_or(0),
+        points().map(|p| p.y).max().unwrap_or(0),
+    ];
+    let mut bits = Bits {
+        bytes: id.to_le_bytes().to_vec(),
+        free: 0,
+    };
+    let count = field_bits(&bounds);
+    if count > WIDEST_FIELD_BITS {
+        return None;
+    }
+    bits.put(count, 5);
+    for value in bounds {
+        bits.signed(value, count);
+    }
+    // Byte-aligned from here: one solid fill style, no line styles, then
+    // one fill-index bit and no line-index bits.
+    bits.free = 0;
+    bits.bytes.extend([1, 0]);
+    bits.bytes.extend(rgba);
+    bits.bytes.extend([0, 0x10]);
+    for (index, contour) in contours.iter().enumerate() {
+        let first = index == 0;
+        bits.put(0, 1);
+        bits.put(
+            if first {
+                FILL_STYLE_0 | MOVE_TO
+            } else {
+                MOVE_TO
+            },
+            5,
+        );
+        let count = field_bits(&[contour.start.x, contour.start.y]);
+        bits.put(count, 5);
+        bits.signed(contour.start.x, count);
+        bits.signed(contour.start.y, count);
+        if first {
+            bits.put(1, 1);
+        }
+        let mut at = contour.start;
+        for edge in &contour.edges {
+            let (line, curve);
+            let (straight, deltas, to): (bool, &[i32], Point) = match *edge {
+                Edge::Line(to) => {
+                    line = delta(at, to)?;
+                    if line == [0, 0] {
+                        continue;
+                    }
+                    (true, &line, to)
+                }
+                Edge::Curve { control, to } => {
+                    let ([cx, cy], [x, y]) = (delta(at, control)?, delta(control, to)?);
+                    curve = [cx, cy, x, y];
+                    (false, &curve, to)
+                }
+            };
+            let count = field_bits(deltas).max(2);
+            if count > WIDEST_EDGE_BITS {
+                return None;
+            }
+            // An edge record: straight or curved, the deltas' width less
+            // two, and for a straight edge its general form (both deltas).
+            bits.put(if straight { 0b11 } else { 0b10 }, 2);
+            bits.put(count - 2, 4);
+            if straight {
+                bits.put(1, 1);
+            }
+            for &value in deltas {
+                bits.signed(value, count);
+            }
+            at = to;
+        }
+    }
+    // The end record: a non-edge record with no flags.
+    bits.put(0, 6);
+    Some(ShapeBody {
+        id,
+        bytes: bits.bytes,
+    })
+}
+
+#[cfg(test)]
+mod tests {
+    use std::collections::HashMap;
+
+    use super::{
+        Change, Contour, DEFINE_SHAPE_3, DEFINE_SPRITE, Depth, END, Edge, Movie, PLACE_OBJECT_2,
+        PLACE_OBJECT_3, Placement, Point, REMOVE_OBJECT_2, SHOW_FRAME, SYMBOL_CLASS, ShapeBody,
+        Sprite, Tag, names_movie, shape, tags,
+    };
+
+    fn tag(code: u16, body: &[u8]) -> Vec<u8> {
+        let mut bytes = ((code << 6) | u16::try_from(body.len()).unwrap())
+            .to_le_bytes()
+            .to_vec();
+        bytes.extend(body);
+        bytes
+    }
+
+    fn long_tag(code: u16, body: &[u8]) -> Vec<u8> {
+        let mut bytes = ((code << 6) | 0x3F).to_le_bytes().to_vec();
+        bytes.extend(u32::try_from(body.len()).unwrap().to_le_bytes());
+        bytes.extend(body);
+        bytes
+    }
+
+    /// A movie: the magic, a version, the length, a frame rectangle of
+    /// 11-bit fields (7 bytes), a rate and a frame count, then the tags.
+    fn movie(tags: &[Vec<u8>]) -> Vec<u8> {
+        let mut bytes = b"GFX\x0b\0\0\0\0".to_vec();
+        bytes.extend([11 << 3, 0, 0, 0, 0, 0, 0]);
+        bytes.extend([0, 30, 1, 0]);
+        bytes.extend(tags.concat());
+        let len = u32::try_from(bytes.len()).unwrap().to_le_bytes();
+        bytes[4..8].copy_from_slice(&len);
+        bytes
+    }
+
+    fn body(id: u16, bytes: &[u8]) -> ShapeBody {
+        ShapeBody {
+            id,
+            bytes: bytes.to_vec(),
+        }
+    }
+
+    fn point(x: i32, y: i32) -> Point {
+        Point { x, y }
+    }
+
+    fn lines(start: Point, to: &[Point]) -> Contour {
+        Contour {
+            start,
+            edges: to.iter().map(|&to| Edge::Line(to)).collect(),
+        }
+    }
+
+    /// The flags of each style change record of a written shape, decoded
+    /// apart from the writer: after the id, the bounds (`bounds_bytes` of
+    /// them) and 8 bytes of styles, records of one fill bit and no line
+    /// bits.
+    fn record_flags(body: &ShapeBody, bounds_bytes: usize) -> Vec<u32> {
+        let bytes = &body.bytes;
+        let mut at = (2 + bounds_bytes + 8) * 8;
+        let mut take = |count: usize| {
+            let mut value = 0;
+            for _ in 0..count {
+                value = (value << 1) | u32::from(bytes[at / 8] >> (7 - at % 8) & 1);
+                at += 1;
+            }
+            value
+        };
+        let mut found = Vec::new();
+        loop {
+            if take(1) == 0 {
+                let flags = take(5);
+                if flags == 0 {
+                    return found;
+                }
+                found.push(flags);
+                if flags & 1 != 0 {
+                    let width = take(5) as usize;
+                    take(2 * width);
+                }
+                take(usize::from(flags & 2 != 0) + usize::from(flags & 4 != 0));
+            } else if take(1) == 1 {
+                let width = take(4) as usize + 2;
+                let both = take(1) == 1;
+                take(if both { 2 * width } else { 1 + width });
+            } else {
+                let width = take(4) as usize + 2;
+                take(4 * width);
+            }
+        }
+    }
+
+    #[test]
+    fn tags_with_short_and_long_headers_are_listed_up_to_the_end_tag() {
+        let movie = movie(&[
+            tag(DEFINE_SPRITE, &[1, 2, 3, 4]),
+            long_tag(DEFINE_SHAPE_3, &[4, 5]),
+            tag(END, &[]),
+            tag(DEFINE_SPRITE, &[9]),
+        ]);
+
+        let parsed = Movie::parse(&movie).unwrap();
+
+        // The first tag starts after 8 header bytes, 7 of the rectangle and 4
+        // of the rate and the frame count.
+        assert_eq!(parsed.first, 19);
+        assert_eq!(
+            parsed.tags,
+            [
+                Tag {
+                    code: DEFINE_SPRITE,
+                    start: 19,
+                    body: 21..25
+                },
+                Tag {
+                    code: DEFINE_SHAPE_3,
+                    start: 25,
+                    body: 31..33
+                },
+                Tag {
+                    code: END,
+                    start: 33,
+                    body: 35..35
+                },
+            ]
+        );
+    }
+
+    #[test]
+    fn a_tag_past_its_range_is_refused() {
+        let bytes = tag(DEFINE_SPRITE, &[1, 2, 3]);
+
+        assert_eq!(tags(&bytes, 0..4), None);
+        assert_eq!(tags(&bytes, 0..1), None);
+        let huge = [0xFF, 0x09, 0xFF, 0xFF, 0xFF, 0xFF];
+        assert_eq!(tags(&huge, 0..huge.len()), None);
+    }
+
+    #[test]
+    fn bytes_that_are_no_movie_are_not_parsed() {
+        let good = movie(&[tag(END, &[])]);
+        let mut compressed = good.clone();
+        compressed[..3].copy_from_slice(b"CFX");
+        let mut wrong_length = good.clone();
+        wrong_length[4] += 1;
+
+        assert!(Movie::parse(&good).is_some());
+        assert!(Movie::parse(&compressed).is_none());
+        assert!(Movie::parse(&wrong_length).is_none());
+        assert!(Movie::parse(b"GFX").is_none());
+        assert!(Movie::parse(&[]).is_none());
+    }
+
+    #[test]
+    fn replacing_a_shape_keeps_every_other_tag_and_fixes_the_length() {
+        let sprite = tag(DEFINE_SPRITE, &[1, 0, 1, 0]);
+        let kept = tag(DEFINE_SHAPE_3, &[8, 0, 0xAA]);
+        let original = movie(&[
+            sprite.clone(),
+            tag(DEFINE_SHAPE_3, &[7, 0, 0xAA]),
+            kept.clone(),
+            tag(END, &[]),
+        ]);
+        let new = [7, 0, 1, 2, 3, 4, 5];
+
+        let replaced = Movie::parse(&original)
+            .unwrap()
+            .replace_shapes(&[body(7, &new)])
+            .unwrap();
+
+        let expected = movie(&[sprite, long_tag(DEFINE_SHAPE_3, &new), kept, tag(END, &[])]);
+        assert_eq!(replaced, expected);
+    }
+
+    #[test]
+    fn a_body_that_names_no_shape_once_is_refused() {
+        let twice = movie(&[
+            tag(DEFINE_SHAPE_3, &[7, 0]),
+            tag(DEFINE_SHAPE_3, &[7, 0]),
+            tag(END, &[]),
+        ]);
+        let once = movie(&[tag(DEFINE_SHAPE_3, &[7, 0]), tag(END, &[])]);
+
+        let twice = Movie::parse(&twice).unwrap();
+        let once = Movie::parse(&once).unwrap();
+
+        assert_eq!(twice.shape_counts(), &HashMap::from([(7, 2)]));
+        assert_eq!(twice.replace_shapes(&[body(7, &[7, 0])]), None);
+        assert_eq!(once.replace_shapes(&[body(8, &[8, 0])]), None);
+        assert_eq!(
+            once.replace_shapes(&[body(7, &[7, 0, 1]), body(7, &[7, 0, 2])]),
+            None
+        );
+    }
+
+    #[test]
+    fn a_shape_tag_too_short_for_an_id_names_no_shape() {
+        // The empty shape's id would otherwise be read from the next tag's
+        // header, which reads as 7.
+        let movie = movie(&[tag(DEFINE_SHAPE_3, &[]), tag(END, &[0; 7])]);
+
+        let parsed = Movie::parse(&movie).unwrap();
+
+        assert!(parsed.shape_counts().is_empty());
+        assert_eq!(parsed.replace_shapes(&[body(7, &[7, 0])]), None);
+    }
+
+    #[test]
+    fn a_sprite_lists_what_each_placement_does_frame_by_frame() {
+        let own = [
+            // Places character 0x0102 at depth 1, with a matrix.
+            tag(PLACE_OBJECT_2, &[0b110, 1, 0, 2, 1, 0]),
+            // Replaces the character at depth 1 with 0x0003.
+            tag(PLACE_OBJECT_2, &[0b011, 1, 0, 3, 0]),
+            // Places character 9 at depth 2 as a mask.
+            tag(PLACE_OBJECT_2, &[0x46, 2, 0, 9, 0]),
+            tag(SHOW_FRAME, &[]),
+            // Moves the character at depth 1.
+            tag(PLACE_OBJECT_2, &[0b101, 1, 0, 0]),
+            tag(REMOVE_OBJECT_2, &[1, 0]),
+            tag(PLACE_OBJECT_3, &[0, 0, 4, 0]),
+            tag(END, &[]),
+        ]
+        .concat();
+        let sprite = [&[5, 0, 2, 0][..], &own].concat();
+        let movie = movie(&[tag(DEFINE_SPRITE, &sprite), tag(END, &[])]);
+
+        let sprites = Movie::parse(&movie).unwrap().sprites();
+
+        let at = |frame, depth, change| Placement {
+            frame,
+            depth: Depth(depth),
+            change,
+        };
+        assert_eq!(
+            sprites,
+            Some(vec![Sprite {
+                id: 5,
+                placements: vec![
+                    at(0, 1, Change::Place(0x0102)),
+                    at(0, 1, Change::Replace(3)),
+                    at(0, 2, Change::Mask(9)),
+                    at(1, 1, Change::Modify),
+                    at(1, 1, Change::Remove),
+                    at(1, 4, Change::Unread),
+                ],
+            }])
+        );
+    }
+
+    #[test]
+    fn a_placement_too_short_for_its_fields_is_refused() {
+        // Names a character, but its body ends after the depth.
+        let own = [tag(PLACE_OBJECT_2, &[0b10, 1, 0]), tag(END, &[])].concat();
+        let sprite = [&[5, 0, 1, 0][..], &own].concat();
+        let movie = movie(&[
+            tag(DEFINE_SPRITE, &sprite),
+            tag(PLACE_OBJECT_2, &[0b10, 1]),
+            tag(END, &[]),
+        ]);
+
+        let parsed = Movie::parse(&movie).unwrap();
+
+        assert_eq!(parsed.sprites(), None);
+        assert_eq!(parsed.timeline(), None);
+    }
+
+    #[test]
+    fn classes_are_read_name_by_name_and_a_cut_table_is_refused() {
+        let table = [&[2, 0, 5, 0][..], b"first\0", &[6, 0], b"second\0"].concat();
+        let good = movie(&[tag(SYMBOL_CLASS, &table), tag(END, &[])]);
+        let cut = movie(&[tag(SYMBOL_CLASS, &table[..table.len() - 1]), tag(END, &[])]);
+
+        assert_eq!(
+            Movie::parse(&good).unwrap().classes(),
+            Some(vec![(5, &b"first"[..]), (6, &b"second"[..])])
+        );
+        assert_eq!(Movie::parse(&cut).unwrap().classes(), None);
+    }
+
+    #[test]
+    fn a_clockwise_triangle_is_filled_with_style_zero() {
+        let triangle = lines(point(0, 0), &[point(20, 0), point(0, 20), point(0, 0)]);
+
+        let body = shape(7, [0xFF; 4], &[triangle]).unwrap();
+
+        assert_eq!(body.id, 7);
+        assert_eq!(
+            body.bytes,
+            [
+                0x07, 0x00, // the id
+                0x30, 0x0A, 0x00, 0xA0, // bounds 0..20 by 0..20 in 6-bit fields
+                0x01, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0x00,
+                0x10, // one solid fill, one fill bit
+                0x0C, 0x27, 0x4A, 0x80, 0x69, 0xB1, 0x4D, 0x20, 0x58,
+                0x00, // move, three lines, end
+            ]
+        );
+    }
+
+    #[test]
+    fn a_curve_is_written_as_a_control_and_an_anchor_delta() {
+        let leaf = Contour {
+            start: point(10, 10),
+            edges: vec![
+                Edge::Curve {
+                    control: point(30, 10),
+                    to: point(30, 30),
+                },
+                Edge::Line(point(10, 10)),
+            ],
+        };
+
+        let body = shape(1, [0, 0, 0, 0xFF], &[leaf]).unwrap();
+
+        assert_eq!(
+            body.bytes,
+            [
+                0x01, 0x00, // the id
+                0x31, 0x4F, 0x14, 0xF0, // bounds 10..30 by 10..30 in 6-bit fields
+                0x01, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00,
+                0x10, // one solid fill, one fill bit
+                0x0C, 0xAA, 0x56, 0x45, 0x00, 0x01, 0x4D, 0x36, 0x58,
+                0x00, // move, a curve, a line, end
+            ]
+        );
+    }
+
+    #[test]
+    fn only_the_first_contour_sets_the_fill_and_every_contour_moves() {
+        let triangle = lines(point(0, 0), &[point(0, 20), point(20, 0), point(0, 0)]);
+        let outer = lines(
+            point(0, 0),
+            &[point(0, 40), point(40, 40), point(40, 0), point(0, 0)],
+        );
+        let hole = lines(
+            point(10, 10),
+            &[point(30, 10), point(30, 30), point(10, 30), point(10, 10)],
+        );
+
+        let triangle = shape(1, [0; 4], &[triangle]).unwrap();
+        let ring = shape(2, [0; 4], &[hole, outer]).unwrap();
+
+        // Bounds of 6-bit fields take 4 bytes, of 7-bit fields 5.
+        assert_eq!(record_flags(&triangle, 4), [0b00011]);
+        assert_eq!(record_flags(&ring, 5), [0b00011, 0b00001]);
+    }
+
+    #[test]
+    fn a_movie_with_a_button_says_so() {
+        let plain = movie(&[tag(END, &[])]);
+        let with_button = movie(&[tag(34, &[1, 0, 0, 0, 0, 0]), tag(END, &[])]);
+
+        assert!(!Movie::parse(&plain).unwrap().defines_buttons());
+        assert!(Movie::parse(&with_button).unwrap().defines_buttons());
+    }
+
+    #[test]
+    fn an_outline_moves_into_other_points() {
+        let contour = lines(point(1, 2), &[point(3, 4), point(1, 2)]);
+
+        let moved = contour.map(|p| [f64::from(p.x) / 2.0, f64::from(p.y)]);
+
+        assert_eq!(moved.start, [0.5, 2.0]);
+        assert_eq!(
+            moved.edges,
+            [Edge::Line([1.5, 4.0]), Edge::Line([0.5, 2.0])]
+        );
+        assert_eq!(
+            moved.points().collect::<Vec<_>>(),
+            [[0.5, 2.0], [1.5, 4.0], [1.5, 4.0], [0.5, 2.0], [0.5, 2.0]]
+        );
+    }
+
+    #[test]
+    fn a_shape_without_contours_is_empty() {
+        let body = shape(0x0102, [0, 0, 0, 0xFF], &[]).unwrap();
+
+        assert_eq!(
+            body.bytes,
+            [
+                0x02, 0x01, 0x08, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x10, 0x00
+            ]
+        );
+    }
+
+    #[test]
+    fn an_edge_too_long_for_its_record_is_refused() {
+        let long = lines(point(0, 0), &[point(1 << 16, 0), point(0, 0)]);
+        let far = lines(
+            point(i32::MAX, 0),
+            &[point(i32::MIN, 0), point(i32::MAX, 0)],
+        );
+
+        assert_eq!(shape(1, [0; 4], &[long]), None);
+        assert_eq!(shape(1, [0; 4], &[far]), None);
+    }
+
+    #[test]
+    fn a_contour_that_does_not_end_where_it_starts_is_refused() {
+        let open = lines(point(0, 0), &[point(20, 0), point(0, 20)]);
+        let empty = lines(point(0, 0), &[]);
+
+        assert_eq!(shape(1, [0; 4], &[open]), None);
+        assert_eq!(shape(1, [0; 4], &[empty]), None);
+    }
+
+    #[test]
+    fn a_header_names_a_movie_of_its_own_length() {
+        let header = *b"GFX\x0b\x20\0\0\0";
+
+        assert!(names_movie(&header, 32));
+        assert!(!names_movie(&header, 31));
+        assert!(!names_movie(b"CFX\x0b\x20\0\0\0", 32));
+    }
+}
diff -ruN -x target -x Cargo.lock -x '*.rej' -x .git a/crates/victory-formats/src/lib.rs b/crates/victory-formats/src/lib.rs
--- a/crates/victory-formats/src/lib.rs	2026-11-27 11:51:28.371168900 -0300
+++ b/crates/victory-formats/src/lib.rs	2026-11-27 19:10:51.332065300 -0300
@@ -1,10 +1,12 @@
-//! Platform-level data formats, shared by every Xbox Series title.
+//! Platform-level data formats of Xbox Series titles and the middleware they ship.
 //!
 //! Each module is pure (bytes in, bytes out, no I/O): [`texture`] (the
-//! GPU's tiled texture layouts and copies to and from linear rows). Planned:
+//! GPU's tiled texture layouts and copies to and from linear rows), [`gfx`]
+//! (the tags and vector shapes of Scaleform UI movies). Planned:
 //! BCPack textures, audio codecs (XMA2, Opus), and the zlib streams used by
 //! hardware decompression.
 
 pub mod bcpack;
+pub mod gfx;
 pub mod texture;
 pub mod xma;
diff -ruN -x target -x Cargo.lock -x '*.rej' -x .git a/crates/victory-game/Cargo.toml b/crates/victory-game/Cargo.toml
--- a/crates/victory-game/Cargo.toml	2026-11-27 11:51:28.372784500 -0300
+++ b/crates/victory-game/Cargo.toml	2026-11-27 19:11:05.894619900 -0300
@@ -10,6 +10,17 @@
 [dependencies]
 memchr.workspace = true
 zlib-rs.workspace = true
+# The keyboard's bindings, for `prompts` (Marvisak/VIctory#3433).
+victory-core.workspace = true
+victory-formats.workspace = true
+
+# The hook of `prompts`: the image it is placed in, the host font, its errors
+# and its log.
+[target.'cfg(windows)'.dependencies]
+thiserror.workspace = true
+tracing.workspace = true
+victory-loader.workspace = true
+windows-sys = { workspace = true, features = ["Win32_Foundation", "Win32_Graphics_Gdi"] }
 
 [lints]
 workspace = true
diff -ruN -x target -x Cargo.lock -x '*.rej' -x .git a/crates/victory-game/src/lib.rs b/crates/victory-game/src/lib.rs
--- a/crates/victory-game/src/lib.rs	2026-11-27 11:51:28.373305600 -0300
+++ b/crates/victory-game/src/lib.rs	2026-11-27 19:11:05.878618800 -0300
@@ -3,6 +3,7 @@
 //! offsets or byte-pattern signatures). What may and may not be stored here
 //! is defined in docs/asset-policy.md.
 
+pub mod prompts;
 pub mod sgd5;
 
 /// A specific build of the title executable we know how to run.
diff -ruN -x target -x Cargo.lock -x '*.rej' -x .git a/crates/victory-game/src/prompts/font.rs b/crates/victory-game/src/prompts/font.rs
--- a/crates/victory-game/src/prompts/font.rs	1969-12-31 21:00:00.000000000 -0300
+++ b/crates/victory-game/src/prompts/font.rs	2026-11-27 19:10:52.083064600 -0300
@@ -0,0 +1,350 @@
+//! Glyph outlines from the host's fonts, for the key caps' labels. It reads
+//! outlines through GDI and draws nothing.
+
+use std::ptr;
+
+use windows_sys::Win32::Graphics::Gdi::{
+    CreateCompatibleDC, CreateFontW, DEFAULT_CHARSET, DeleteDC, DeleteObject, FIXED, FW_BOLD,
+    GGI_MARK_NONEXISTING_GLYPHS, GGO_NATIVE, GGO_UNHINTED, GLYPHMETRICS, GetGlyphIndicesW,
+    GetGlyphOutlineW, HDC, HFONT, MAT2, SelectObject, TT_PRIM_LINE, TT_PRIM_QSPLINE,
+};
+
+use victory_formats::gfx::{Contour, Edge};
+
+use super::{EmPoint, Glyph};
+
+/// A face of the host the labels are drawn with; both ship with Windows.
+#[derive(Clone, Copy, Debug)]
+enum Face {
+    /// Segoe UI in bold, for letters and arrows: heavy, like the letters of
+    /// the title's own button pictures.
+    Letters,
+    /// Segoe UI Symbol, for the signs of Enter and Backspace, which the
+    /// first face lacks.
+    Signs,
+}
+
+impl Face {
+    fn name(self) -> &'static str {
+        match self {
+            Self::Letters => "Segoe UI",
+            Self::Signs => "Segoe UI Symbol",
+        }
+    }
+}
+
+/// The faces labels are drawn with, each opened when the host has it.
+pub(super) struct Fonts {
+    letters: Option<Font>,
+    signs: Option<Font>,
+}
+
+impl Fonts {
+    pub(super) fn open() -> Self {
+        Self {
+            letters: Font::open(Face::Letters),
+            signs: Font::open(Face::Signs),
+        }
+    }
+
+    /// The character's outline from the first face that has it.
+    pub(super) fn glyph(&self, character: char) -> Option<Glyph> {
+        let from = |font: &Option<Font>| font.as_ref()?.glyph(character);
+        from(&self.letters).or_else(|| from(&self.signs))
+    }
+}
+/// The size outlines are taken at.
+const EM_PIXELS: i32 = 1024;
+/// The largest outline taken.
+const LARGEST_OUTLINE_BYTES: u32 = 1 << 20;
+/// The glyph index GDI gives a character the font lacks.
+const MISSING_GLYPH: u16 = 0xFFFF;
+/// What `GetGlyphOutlineW` returns on failure (`GDI_ERROR`).
+const OUTLINE_FAILED: u32 = u32::MAX;
+
+/// A host face, selected into a memory device context.
+struct Font {
+    dc: HDC,
+    font: HFONT,
+}
+
+impl Font {
+    fn open(face: Face) -> Option<Self> {
+        let face: Vec<u16> = face.name().encode_utf16().chain([0]).collect();
+        // SAFETY: plain GDI calls; `face` is NUL-terminated and outlives the
+        // call that reads it.
+        unsafe {
+            let dc = CreateCompatibleDC(ptr::null_mut());
+            if dc.is_null() {
+                return None;
+            }
+            let font = CreateFontW(
+                -EM_PIXELS,
+                0,
+                0,
+                0,
+                FW_BOLD.cast_signed(),
+                0,
+                0,
+                0,
+                u32::from(DEFAULT_CHARSET),
+                0,
+                0,
+                0,
+                0,
+                face.as_ptr(),
+            );
+            if font.is_null() {
+                DeleteDC(dc);
+                return None;
+            }
+            SelectObject(dc, font);
+            Some(Self { dc, font })
+        }
+    }
+
+    /// The character's outline; `None` when the font has no glyph for it.
+    fn glyph(&self, character: char) -> Option<Glyph> {
+        let mut units = [0u16; 2];
+        let [unit] = *character.encode_utf16(&mut units) else {
+            return None;
+        };
+        let one = FIXED { fract: 0, value: 1 };
+        let zero = FIXED { fract: 0, value: 0 };
+        let identity = MAT2 {
+            eM11: one,
+            eM12: zero,
+            eM21: zero,
+            eM22: one,
+        };
+        let format = GGO_NATIVE | GGO_UNHINTED;
+        let mut index = MISSING_GLYPH;
+        let mut metrics = GLYPHMETRICS::default();
+        // SAFETY: one UTF-16 unit in and one index out; the outline call
+        // with no buffer only measures.
+        let size = unsafe {
+            GetGlyphIndicesW(
+                self.dc,
+                &raw const unit,
+                1,
+                &raw mut index,
+                GGI_MARK_NONEXISTING_GLYPHS,
+            );
+            if index == MISSING_GLYPH {
+                return None;
+            }
+            GetGlyphOutlineW(
+                self.dc,
+                u32::from(unit),
+                format,
+                &raw mut metrics,
+                0,
+                ptr::null_mut(),
+                &raw const identity,
+            )
+        };
+        if size == OUTLINE_FAILED || size > LARGEST_OUTLINE_BYTES {
+            return None;
+        }
+        let mut bytes = vec![0u8; usize::try_from(size).ok()?];
+        // SAFETY: the buffer is `size` bytes, the size the call just asked
+        // for.
+        let written = unsafe {
+            GetGlyphOutlineW(
+                self.dc,
+                u32::from(unit),
+                format,
+                &raw mut metrics,
+                size,
+                bytes.as_mut_ptr().cast(),
+                &raw const identity,
+            )
+        };
+        if written != size {
+            return None;
+        }
+        Some(Glyph {
+            contours: contours(&bytes)?,
+            advance_ems: f64::from(metrics.gmCellIncX) / f64::from(EM_PIXELS),
+        })
+    }
+}
+
+impl Drop for Font {
+    fn drop(&mut self) {
+        // SAFETY: both handles are ours and not used after this.
+        unsafe {
+            DeleteDC(self.dc);
+            DeleteObject(self.font);
+        }
+    }
+}
+
+/// The contours of a native glyph outline: polygon records (a size, a type
+/// and a start point) of curve records (a kind, a count and that many
+/// points), every point a pair of 16.16 fixed-point pixels.
+fn contours(bytes: &[u8]) -> Option<Vec<Contour<EmPoint>>> {
+    let word = |at: usize| Some(u16::from_le_bytes(*bytes.get(at..)?.first_chunk()?));
+    let long = |at: usize| Some(u32::from_le_bytes(*bytes.get(at..)?.first_chunk()?));
+    let point = |at: usize| -> Option<EmPoint> {
+        let fixed =
+            |at: usize| Some(f64::from(long(at)?.cast_signed()) / 65536.0 / f64::from(EM_PIXELS));
+        Some([fixed(at)?, fixed(at.checked_add(4)?)?])
+    };
+    let mut found = Vec::new();
+    let mut at = 0usize;
+    while at < bytes.len() {
+        let size = usize::try_from(long(at)?).ok()?;
+        let end = at
+            .checked_add(size)
+            .filter(|&end| size >= 16 && end <= bytes.len())?;
+        let start = point(at + 8)?;
+        let mut edges = Vec::new();
+        let mut from = start;
+        let mut record = at + 16;
+        while record < end {
+            let (kind, count) = (u32::from(word(record)?), usize::from(word(record + 2)?));
+            let next = record + 4 + count * 8;
+            if next > end {
+                return None;
+            }
+            let points = (0..count)
+                .map(|i| point(record + 4 + i * 8))
+                .collect::<Option<Vec<_>>>()?;
+            match kind {
+                TT_PRIM_LINE => edges.extend(points.iter().map(|&to| Edge::Line(to))),
+                // A spline's points are controls, each curve ending midway
+                // to the next control, and the last point is the last end.
+                TT_PRIM_QSPLINE => edges.extend(points.windows(2).enumerate().map(|(i, pair)| {
+                    let (control, next) = (pair[0], pair[1]);
+                    let to = if i + 2 == points.len() {
+                        next
+                    } else {
+                        [(control[0] + next[0]) / 2.0, (control[1] + next[1]) / 2.0]
+                    };
+                    Edge::Curve { control, to }
+                })),
+                _ => return None,
+            }
+            from = edges
+                .last()
+                .map_or(from, |edge: &Edge<EmPoint>| edge.points()[1]);
+            record = next;
+        }
+        if from != start {
+            edges.push(Edge::Line(start));
+        }
+        found.push(Contour { start, edges });
+        at = end;
+    }
+    Some(found)
+}
+
+#[cfg(test)]
+mod tests {
+    use victory_core::pad::fallback_key;
+
+    use super::super::{ICONS, key_label};
+    use victory_formats::gfx::{Contour, Edge};
+
+    use super::{EM_PIXELS, Fonts, contours};
+
+    #[test]
+    fn the_host_font_outlines_every_label_character_within_its_advance() {
+        let fonts = Fonts::open();
+        let characters: Vec<char> = ICONS
+            .iter()
+            .flat_map(|(_, controls)| controls.iter())
+            .filter_map(|&control| key_label(fallback_key(control)))
+            .flat_map(str::chars)
+            .collect();
+
+        for character in characters {
+            let glyph = fonts
+                .glyph(character)
+                .unwrap_or_else(|| panic!("{character}"));
+            let advance = glyph.advance_ems;
+            assert!(advance > 0.1 && advance < 1.5, "{character} {advance}");
+            assert!(!glyph.contours.is_empty(), "{character}");
+            // Ems, not the font's design units: the outline stays within
+            // the pen's advance and about an em of height.
+            for contour in &glyph.contours {
+                for [x, y] in contour.points() {
+                    assert!((-0.1..=advance + 0.1).contains(&x), "{character} x {x}");
+                    assert!((-0.4..=1.2).contains(&y), "{character} y {y}");
+                }
+            }
+        }
+    }
+
+    fn fixed(pixels: i32) -> [u8; 4] {
+        (pixels << 16).to_le_bytes()
+    }
+
+    fn point(x: i32, y: i32) -> Vec<u8> {
+        [fixed(x), fixed(y)].concat()
+    }
+
+    #[test]
+    fn a_polygon_of_a_line_and_a_spline_is_closed_back_to_its_start() {
+        let em = EM_PIXELS;
+        let mut bytes = Vec::new();
+        // One polygon: 16 header bytes, a line record of one point and a
+        // spline record of three points.
+        bytes.extend(56u32.to_le_bytes());
+        bytes.extend(24u32.to_le_bytes());
+        bytes.extend(point(0, 0));
+        bytes.extend([1, 0, 1, 0]);
+        bytes.extend(point(em, 0));
+        bytes.extend([2, 0, 3, 0]);
+        bytes.extend(point(em, em));
+        bytes.extend(point(0, em));
+        bytes.extend(point(0, em / 2));
+
+        assert_eq!(
+            contours(&bytes),
+            Some(vec![Contour {
+                start: [0.0, 0.0],
+                edges: vec![
+                    Edge::Line([1.0, 0.0]),
+                    Edge::Curve {
+                        control: [1.0, 1.0],
+                        to: [0.5, 1.0]
+                    },
+                    Edge::Curve {
+                        control: [0.0, 1.0],
+                        to: [0.0, 0.5]
+                    },
+                    Edge::Line([0.0, 0.0]),
+                ],
+            }])
+        );
+    }
+
+    #[test]
+    fn a_record_past_the_buffer_is_refused() {
+        let mut bytes = Vec::new();
+        bytes.extend(64u32.to_le_bytes());
+        bytes.extend(24u32.to_le_bytes());
+        bytes.extend(point(0, 0));
+
+        assert_eq!(contours(&bytes), None);
+    }
+
+    #[test]
+    fn a_curve_count_past_its_polygon_is_refused() {
+        // The first polygon's line names two points and holds one; the
+        // second point would be the next polygon's header.
+        let mut bytes = Vec::new();
+        bytes.extend(28u32.to_le_bytes());
+        bytes.extend(24u32.to_le_bytes());
+        bytes.extend(point(0, 0));
+        bytes.extend([1, 0, 2, 0]);
+        bytes.extend(point(1, 1));
+        bytes.extend(16u32.to_le_bytes());
+        bytes.extend(24u32.to_le_bytes());
+        bytes.extend(point(0, 0));
+
+        assert_eq!(contours(&bytes), None);
+    }
+}
diff -ruN -x target -x Cargo.lock -x '*.rej' -x .git a/crates/victory-game/src/prompts/hook.rs b/crates/victory-game/src/prompts/hook.rs
--- a/crates/victory-game/src/prompts/hook.rs	1969-12-31 21:00:00.000000000 -0300
+++ b/crates/victory-game/src/prompts/hook.rs	2026-11-27 19:10:52.131011600 -0300
@@ -0,0 +1,649 @@
+//! Hands the redrawn icon movie to the title.
+//!
+//! The UI runtime asks one title function, through a pointer, for the address
+//! of every movie it loads. [`install`] puts [`movie_address`] in that
+//! pointer. The streaming store hands a movie over as an address in memory;
+//! when that movie is the icon movie, a redrawn copy is kept. A movie that
+//! later loads the icon movie by name is answered with the copy's address;
+//! one that asks while the copy is still being drawn gets the original.
+//! Nothing else about a request changes.
+
+use std::cell::OnceCell;
+use std::ffi::{CString, c_char, c_void};
+use std::mem::offset_of;
+use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
+use std::sync::{Mutex, MutexGuard, OnceLock, PoisonError};
+
+use victory_formats::gfx;
+use victory_loader::{LoadedImage, SlotError};
+
+use super::{HookOffsets, Refusal, font::Fonts, key_caps};
+
+/// The size of the buffer a string's text is read into: text of 511 bytes
+/// and its NUL at most.
+const TEXT_BUFFER_BYTES: usize = 512;
+/// The largest movie copied: the icon movie is 28 KB (Series 1.0.2.1), and
+/// a larger one costs a copy and a parse on the loading thread for nothing.
+const LARGEST_MOVIE_BYTES: usize = 256 << 10;
+/// The most distinct icon movies redrawn in one run; the title has one.
+const MOST_DRAWN: usize = 8;
+/// The most places in the store remembered at once; the oldest go first.
+const MOST_STORED: usize = 64;
+/// A UI runtime string is a pointer to a block, with flags in these bits
+/// (seen in the strings the title passes, Series 1.0.2.1).
+const STRING_FLAG_MASK: usize = 3;
+/// Where the text starts in a string's block, after a size and a count
+/// (seen there too).
+const STRING_TEXT_OFFSET_BYTES: usize = 12;
+
+/// A UI runtime string: a pointer to a block, with flags in its low bits.
+#[repr(transparent)]
+#[derive(Clone, Copy, Debug)]
+struct UiString(usize);
+
+/// The start of what the UI runtime passes to describe the movie it wants:
+/// the kind of request and the movie's name. The parent's path follows, and
+/// is not read.
+#[repr(C)]
+struct Location {
+    kind: u32,
+    name: UiString,
+}
+
+const _: () = assert!(offset_of!(Location, kind) == 0 && offset_of!(Location, name) == 8);
+
+/// The requests the hook acts on, by the kind the record names (seen in the
+/// title's requests while its first screen loads, Series 1.0.2.1).
+#[derive(Clone, Copy, Debug, PartialEq, Eq)]
+enum Request {
+    /// Kind 0: the streaming store has just read the movie into memory.
+    HandedOver,
+    /// Kind 3: a movie loads another movie by name.
+    LoadedByAMovie,
+}
+
+impl TryFrom<u32> for Request {
+    type Error = u32;
+
+    fn try_from(kind: u32) -> Result<Self, u32> {
+        match kind {
+            0 => Ok(Self::HandedOver),
+            3 => Ok(Self::LoadedByAMovie),
+            other => Err(other),
+        }
+    }
+}
+
+type BuildAddress = unsafe extern "system" fn(*mut c_void, *mut UiString, *const Location);
+type AssignString = unsafe extern "system" fn(*mut UiString, *const c_char);
+
+/// The title's own functions, set once before the pointer is replaced.
+struct Title {
+    build_address: BuildAddress,
+    assign_string: AssignString,
+}
+
+static TITLE: OnceLock<Title> = OnceLock::new();
+
+/// Whether a movie has been answered with a copy yet, so that the first
+/// answer is logged.
+static SERVED: AtomicBool = AtomicBool::new(false);
+
+/// Warnings logged once each, however often their cause comes back.
+#[derive(Clone, Copy, Debug)]
+enum Warning {
+    Unreadable,
+    NothingDrawn,
+    TooManyMovies,
+}
+
+static WARNED: AtomicU8 = AtomicU8::new(0);
+
+fn warn_once(warning: Warning) {
+    let bit = 1 << warning as u8;
+    if WARNED.fetch_or(bit, Ordering::Relaxed) & bit == 0 {
+        tracing::warn!(
+            ?warning,
+            "prompts: the icon movie keeps its gamepad pictures"
+        );
+    }
+}
+
+/// A movie the store handed over and our redrawn copy of it.
+struct Drawn {
+    original: Box<[u8]>,
+    redrawn: &'static [u8],
+}
+
+/// Where the store keeps a movie we have a redrawn copy of.
+struct Stored {
+    tag: String,
+    address: usize,
+    len: usize,
+    redrawn: &'static [u8],
+}
+
+/// The redrawn movies, one per distinct original; icon movies that could
+/// not be redrawn; and where the store keeps each original. A redrawn movie
+/// is never freed: the title may read it for as long as it runs.
+struct Kept {
+    drawn: Vec<Drawn>,
+    refused: Vec<Box<[u8]>>,
+    stored: Vec<Stored>,
+}
+
+/// Held only to look up or change an entry: never across a call into the
+/// title, a redraw or a log line.
+static KEPT: Mutex<Kept> = Mutex::new(Kept {
+    drawn: Vec::new(),
+    refused: Vec::new(),
+    stored: Vec::new(),
+});
+
+fn kept() -> MutexGuard<'static, Kept> {
+    KEPT.lock().unwrap_or_else(PoisonError::into_inner)
+}
+
+/// Why the hook was not placed.
+#[derive(Debug, thiserror::Error)]
+pub enum Refused {
+    #[error("the pointer does not lead to code of the image")]
+    NotATitlePointer,
+    #[error("the hook is already placed")]
+    AlreadyPlaced,
+    #[error(transparent)]
+    Slot(#[from] SlotError),
+}
+
+/// Replaces the title's movie address pointer with [`movie_address`]. The
+/// pointer is read and checked, and the title's functions kept, before it
+/// is written.
+///
+/// # Safety
+///
+/// `image` is the mapped and bound image of the build `offsets` belong to,
+/// and no title thread runs yet.
+pub unsafe fn install(image: &LoadedImage, offsets: HookOffsets) -> Result<(), Refused> {
+    let assign_string = image.code_address(offsets.string_assign.0)?;
+    let slot = offsets.movie_address_builder.0;
+    // SAFETY: no title thread runs, per the caller.
+    let build_address = unsafe { image.read_pointer(slot) }?;
+    let builder_offset = build_address
+        .checked_sub(image.base())
+        .and_then(|offset| u32::try_from(offset).ok())
+        .ok_or(Refused::NotATitlePointer)?;
+    if image.code_address(builder_offset).is_err() {
+        return Err(Refused::NotATitlePointer);
+    }
+    // SAFETY: both addresses are code of the build the offsets belong to,
+    // checked to lie in its code sections, and the types are those
+    // functions' arguments.
+    let title = unsafe {
+        Title {
+            build_address: std::mem::transmute::<usize, BuildAddress>(build_address),
+            assign_string: std::mem::transmute::<usize, AssignString>(assign_string),
+        }
+    };
+    TITLE.set(title).map_err(|_| Refused::AlreadyPlaced)?;
+    let hook: BuildAddress = movie_address;
+    // SAFETY: no title thread runs, per the caller.
+    unsafe { image.write_pointer(slot, hook as usize) }?;
+    Ok(())
+}
+
+/// A movie in memory, as the title's address text names it:
+/// `memory:$<address, hex>,<length>,<number>:<tag>`.
+#[derive(Debug, PartialEq, Eq)]
+struct InMemory<'a> {
+    address: usize,
+    len: usize,
+    tag: &'a str,
+}
+
+impl<'a> InMemory<'a> {
+    /// `None` when the text names no movie, or one shorter than a movie's
+    /// header or larger than this module copies.
+    fn parse(text: &'a str) -> Option<Self> {
+        let (fields, tag) = text.strip_prefix("memory:$")?.split_once(':')?;
+        let mut fields = fields.split(',');
+        let address = usize::from_str_radix(fields.next()?, 16).ok()?;
+        let len: usize = fields.next()?.parse().ok()?;
+        (address != 0 && (gfx::HEADER_BYTES..=LARGEST_MOVIE_BYTES).contains(&len)).then_some(Self {
+            address,
+            len,
+            tag,
+        })
+    }
+}
+
+/// The address text for one of our movies, tagged with the name the movie
+/// was asked for by. With the store's own tag in the text instead, the
+/// title's screen stayed black (Series 1.0.2.1, measured).
+fn address_text(movie: &[u8], name: &str) -> Option<CString> {
+    CString::new(format!(
+        "memory:${:016X},{},0:victory:{name}",
+        movie.as_ptr().addr(),
+        movie.len()
+    ))
+    .ok()
+}
+
+/// The text of a UI runtime string, read into a buffer of our own.
+struct UiText {
+    bytes: [u8; TEXT_BUFFER_BYTES],
+    len: usize,
+}
+
+impl UiText {
+    fn as_str(&self) -> &str {
+        self.bytes
+            .get(..self.len)
+            .and_then(|text| std::str::from_utf8(text).ok())
+            .unwrap_or_default()
+    }
+
+    /// The text of `string`. `None` when it is empty, does not fit the
+    /// buffer with its NUL, or is not UTF-8.
+    ///
+    /// # Safety
+    ///
+    /// `string` is a live UI runtime string that no other thread changes.
+    unsafe fn read(string: UiString) -> Option<Self> {
+        let block = string.0 & !STRING_FLAG_MASK;
+        if block == 0 {
+            return None;
+        }
+        let from = block.checked_add(STRING_TEXT_OFFSET_BYTES)? as *const u8;
+        let mut text = Self {
+            bytes: [0; TEXT_BUFFER_BYTES],
+            len: 0,
+        };
+        for at in 0..TEXT_BUFFER_BYTES {
+            // SAFETY: the text ends in a NUL, and the read stops at it.
+            let byte = unsafe { from.add(at).read() };
+            if byte == 0 {
+                text.len = at;
+                let valid = std::str::from_utf8(text.bytes.get(..at)?).is_ok();
+                return (valid && at > 0).then_some(text);
+            }
+            *text.bytes.get_mut(at)? = byte;
+        }
+        None
+    }
+}
+
+/// A copy of the movie at `memory`; `None` when its header does not name
+/// an uncompressed movie of that length.
+///
+/// # Safety
+///
+/// `memory` names bytes the title holds readable for this call.
+unsafe fn copy_of(memory: &InMemory) -> Option<Box<[u8]>> {
+    let from = memory.address as *const u8;
+    // SAFETY: the first bytes of the ones the title names; `InMemory`
+    // names at least a header's worth.
+    let header = unsafe { from.cast::<[u8; gfx::HEADER_BYTES]>().read_unaligned() };
+    if !gfx::names_movie(&header, memory.len) {
+        return None;
+    }
+    let mut copy = Vec::with_capacity(memory.len);
+    // SAFETY: the title names these bytes, and the copy has room for them;
+    // they are copied, since the store reuses its buffer.
+    unsafe {
+        from.copy_to_nonoverlapping(copy.as_mut_ptr(), memory.len);
+        copy.set_len(memory.len);
+    }
+    Some(copy.into_boxed_slice())
+}
+
+/// The redrawn copy of `original`, drawn once for each distinct original.
+/// `None` when it is not the icon movie or cannot be drawn; an icon movie
+/// that cannot be drawn is remembered, and not tried again.
+fn redrawn(original: Box<[u8]>) -> Option<&'static [u8]> {
+    let drawn_before = |kept: &Kept| {
+        kept.drawn
+            .iter()
+            .find(|drawn| drawn.original == original)
+            .map(|drawn| drawn.redrawn)
+    };
+    {
+        let kept = kept();
+        if let Some(redrawn) = drawn_before(&kept) {
+            return Some(redrawn);
+        }
+        if kept.refused.contains(&original) {
+            return None;
+        }
+        if kept.drawn.len() >= MOST_DRAWN {
+            drop(kept);
+            warn_once(Warning::TooManyMovies);
+            return None;
+        }
+    }
+    let fonts = OnceCell::new();
+    let glyph = |character| fonts.get_or_init(Fonts::open).glyph(character);
+    let warning = match key_caps(&original, &glyph) {
+        Ok(drawn) => {
+            let drawn = drawn.into_boxed_slice();
+            let mut kept = kept();
+            if let Some(redrawn) = drawn_before(&kept) {
+                return Some(redrawn);
+            }
+            let redrawn: &'static [u8] = Box::leak(drawn);
+            kept.drawn.push(Drawn { original, redrawn });
+            drop(kept);
+            tracing::info!(
+                bytes = redrawn.len(),
+                "prompts: key caps drawn into the icon movie"
+            );
+            return Some(redrawn);
+        }
+        Err(Refusal::NotIconMovie) => return None,
+        Err(Refusal::Unreadable) => Warning::Unreadable,
+        Err(Refusal::NothingDrawn) => Warning::NothingDrawn,
+    };
+    let mut kept = kept();
+    if kept.refused.len() < MOST_DRAWN && !kept.refused.contains(&original) {
+        kept.refused.push(original);
+    }
+    drop(kept);
+    warn_once(warning);
+    None
+}
+
+/// Keeps a redrawn copy of the movie at `memory` when it is the icon movie,
+/// and forgets what the store kept under its tag before.
+///
+/// # Safety
+///
+/// `memory` names bytes the title holds readable for this call.
+unsafe fn keep(memory: &InMemory) {
+    // SAFETY: forwarded from the caller.
+    let redrawn = unsafe { copy_of(memory) }.and_then(redrawn);
+    let mut kept = kept();
+    kept.stored.retain(|stored| stored.tag != memory.tag);
+    let Some(redrawn) = redrawn else {
+        return;
+    };
+    if kept.stored.len() >= MOST_STORED {
+        kept.stored.remove(0);
+    }
+    kept.stored.push(Stored {
+        tag: memory.tag.to_owned(),
+        address: memory.address,
+        len: memory.len,
+        redrawn,
+    });
+}
+
+/// The redrawn copy of the movie the store keeps at `memory`.
+fn served(memory: &InMemory) -> Option<&'static [u8]> {
+    kept()
+        .stored
+        .iter()
+        .find(|stored| {
+            stored.tag == memory.tag && stored.address == memory.address && stored.len == memory.len
+        })
+        .map(|stored| stored.redrawn)
+}
+
+/// Answers a movie that loads the icon movie by name with our copy.
+fn serve(title: &Title, out: *mut UiString, name: UiString, memory: &InMemory) {
+    let Some(movie) = served(memory) else {
+        return;
+    };
+    // SAFETY: the name in the caller's record, owned by the caller.
+    let Some(text) =
+        unsafe { UiText::read(name) }.and_then(|name| address_text(movie, name.as_str()))
+    else {
+        return;
+    };
+    // SAFETY: the title's own string assignment on the answer string, the
+    // way the title's function has just assigned it; the text is copied.
+    unsafe { (title.assign_string)(out, text.as_ptr()) };
+    if !SERVED.swap(true, Ordering::Relaxed) {
+        tracing::info!("prompts: the title loads the icon movie with key caps");
+    }
+}
+
+/// The title's movie address function, with the icon movie's address
+/// replaced by our copy's.
+///
+/// The UI runtime calls it from any thread that loads a movie. It takes the
+/// [`KEPT`] lock to look up or change an entry, and redraws a movie the
+/// store hands over outside it.
+extern "system" fn movie_address(this: *mut c_void, out: *mut UiString, location: *const Location) {
+    let Some(title) = TITLE.get() else {
+        return;
+    };
+    // SAFETY: the title's own function with the title's own arguments.
+    unsafe { (title.build_address)(this, out, location) };
+    if out.is_null() || location.is_null() {
+        return;
+    }
+    // SAFETY: the caller's record and its answer string, which the caller
+    // owns for this call.
+    let (Location { kind, name }, answer) =
+        unsafe { (location.read_unaligned(), out.read_unaligned()) };
+    let Ok(request) = Request::try_from(kind) else {
+        return;
+    };
+    // SAFETY: the answer the title has just assigned, owned by the caller.
+    let Some(answer) = (unsafe { UiText::read(answer) }) else {
+        return;
+    };
+    let Some(memory) = InMemory::parse(answer.as_str()) else {
+        return;
+    };
+    match request {
+        // SAFETY: the store has just read the movie into the bytes it names.
+        Request::HandedOver => unsafe { keep(&memory) },
+        Request::LoadedByAMovie => serve(title, out, name, &memory),
+    }
+}
+
+#[cfg(test)]
+mod tests {
+    use std::ffi::{CStr, c_char, c_void};
+    use std::sync::Mutex;
+
+    use super::super::fixtures::{icon_movie, known_icons};
+    use super::{
+        InMemory, LARGEST_MOVIE_BYTES, Location, Request, TEXT_BUFFER_BYTES, TITLE, Title,
+        UiString, UiText, address_text, movie_address,
+    };
+
+    /// A UI runtime string block: twelve bytes of header, then the text and
+    /// its NUL, in words so that it is aligned like the title's.
+    fn block(text: &[u8]) -> Vec<u64> {
+        let mut bytes = vec![0u8; 12];
+        bytes.extend(text);
+        bytes.push(0);
+        bytes.resize(bytes.len().next_multiple_of(8), 0);
+        let (words, _) = bytes.as_chunks::<8>();
+        words.iter().map(|word| u64::from_le_bytes(*word)).collect()
+    }
+
+    fn string(block: &[u64]) -> UiString {
+        UiString(block.as_ptr().addr())
+    }
+
+    #[test]
+    fn an_address_in_memory_gives_its_address_length_and_tag() {
+        assert_eq!(
+            InMemory::parse("memory:$00000000DEADBEEF,300,0:tag-one"),
+            Some(InMemory {
+                address: 0xDEAD_BEEF,
+                len: 300,
+                tag: "tag-one",
+            })
+        );
+    }
+
+    #[test]
+    fn other_addresses_are_not_in_memory() {
+        for text in [
+            "disk:/our/movie",
+            "memory:$0000000000000000,10,0:tag",
+            "memory:$00000000DEADBEEF,0,0:tag",
+            "memory:$00000000DEADBEEF,7,0:tag",
+            "memory:$00000000DEADBEEF,ten,0:tag",
+            "memory:$00000000DEADBEEF,10,0",
+            "memory:$XYZ,10,0:tag",
+        ] {
+            assert_eq!(InMemory::parse(text), None, "{text}");
+        }
+        let too_large = format!("memory:$00000000DEADBEEF,{},0:tag", LARGEST_MOVIE_BYTES + 1);
+        assert_eq!(InMemory::parse(&too_large), None);
+        assert!(InMemory::parse("memory:$00000000DEADBEEF,8,0:tag").is_some());
+    }
+
+    #[test]
+    fn our_address_text_parses_back_to_our_movie() {
+        let movie = [1u8; 9];
+
+        let text = address_text(&movie, "our.movie").unwrap();
+
+        assert_eq!(
+            InMemory::parse(text.to_str().unwrap()),
+            Some(InMemory {
+                address: movie.as_ptr().addr(),
+                len: 9,
+                tag: "victory:our.movie",
+            })
+        );
+    }
+
+    #[test]
+    fn a_string_gives_its_text_whatever_its_flag_bits() {
+        let block = block(b"memory:$1,2,0:tag");
+
+        // SAFETY: the block is ours and ends in a NUL.
+        let read = unsafe { UiText::read(UiString(block.as_ptr().addr() | 2)) };
+
+        assert_eq!(read.as_ref().map(UiText::as_str), Some("memory:$1,2,0:tag"));
+    }
+
+    #[test]
+    fn a_null_an_empty_an_overlong_or_a_wrapping_string_gives_nothing() {
+        let empty = block(b"");
+        let longest = block(&[b'a'; TEXT_BUFFER_BYTES - 1]);
+        let overlong = block(&[b'a'; TEXT_BUFFER_BYTES]);
+
+        // SAFETY: a null string and one whose text would start past the end
+        // of the address space are not read; the blocks are ours, end in a
+        // NUL and are read no further than it.
+        let read = unsafe {
+            [
+                UiText::read(UiString(1)).is_some(),
+                UiText::read(UiString(usize::MAX)).is_some(),
+                UiText::read(string(&empty)).is_some(),
+                UiText::read(string(&longest)).is_some(),
+                UiText::read(string(&overlong)).is_some(),
+            ]
+        };
+
+        assert_eq!(read, [false, false, false, true, false]);
+    }
+
+    #[test]
+    fn only_two_kinds_of_request_are_acted_on() {
+        assert_eq!(Request::try_from(0), Ok(Request::HandedOver));
+        assert_eq!(Request::try_from(3), Ok(Request::LoadedByAMovie));
+        for kind in [1, 2, 4, u32::MAX] {
+            assert_eq!(Request::try_from(kind), Err(kind));
+        }
+    }
+
+    /// A stand-in for the title's function: the answer is the string its
+    /// first argument names.
+    unsafe extern "system" fn build_address(
+        this: *mut c_void,
+        out: *mut UiString,
+        _: *const Location,
+    ) {
+        // SAFETY: the test passes a live answer slot.
+        unsafe { out.write(UiString(this.addr())) };
+    }
+
+    static ASSIGNED: Mutex<Vec<String>> = Mutex::new(Vec::new());
+
+    /// A stand-in for the title's string assignment: it records the text.
+    unsafe extern "system" fn assign_string(_: *mut UiString, text: *const c_char) {
+        // SAFETY: the hook passes NUL-terminated text.
+        let text = unsafe { CStr::from_ptr(text) }.to_str().unwrap().to_owned();
+        ASSIGNED.lock().unwrap().push(text);
+    }
+
+    /// Asks the hook as the UI runtime would: `kind` of request, the name
+    /// `name` names, and the store's answer `answer` names. Returns the
+    /// texts the hook assigned.
+    fn ask(kind: u32, name: &[u64], answer: &[u64]) -> Vec<String> {
+        let location = Location {
+            kind,
+            name: string(name),
+        };
+        let mut out = UiString(0);
+        movie_address(
+            answer.as_ptr().cast_mut().cast(),
+            &raw mut out,
+            &raw const location,
+        );
+        assert_eq!(out.0, answer.as_ptr().addr());
+        std::mem::take(&mut *ASSIGNED.lock().unwrap())
+    }
+
+    fn in_memory(movie: &[u8], tag: &str) -> Vec<u64> {
+        block(
+            format!(
+                "memory:${:016X},{},0:{tag}",
+                movie.as_ptr().addr(),
+                movie.len()
+            )
+            .as_bytes(),
+        )
+    }
+
+    #[test]
+    fn a_movie_loaded_by_name_is_answered_with_the_redrawn_copy_of_what_the_store_holds() {
+        assert!(
+            TITLE
+                .set(Title {
+                    build_address,
+                    assign_string,
+                })
+                .is_ok()
+        );
+        let name = block(b"our.movie");
+        let icons = icon_movie(&known_icons());
+        let again = icons.clone();
+        let other = [&b"GFX\x0b"[..], &13u32.to_le_bytes(), &[0; 5]].concat();
+        let (one, two) = (in_memory(&icons, "tag-one"), in_memory(&again, "tag-two"));
+
+        // Nothing is kept yet: the title's answer stands.
+        assert_eq!(ask(3, &name, &one), [""; 0]);
+
+        assert_eq!(ask(0, &name, &one), [""; 0]);
+        let served = ask(3, &name, &one);
+        assert_eq!(served.len(), 1);
+        let ours = InMemory::parse(&served[0]).unwrap();
+        assert_eq!(ours.tag, "victory:our.movie");
+        assert_ne!(ours.address, icons.as_ptr().addr());
+        // Only a movie loaded by a movie is answered with the copy.
+        assert_eq!(ask(2, &name, &one), [""; 0]);
+
+        // The same movie under another tag shares the copy.
+        assert_eq!(ask(0, &name, &two), [""; 0]);
+        assert_eq!(ask(3, &name, &two), served);
+
+        // The tag at another address is not the movie the copy was made of.
+        let moved = in_memory(&again, "tag-one");
+        assert_eq!(ask(3, &name, &moved), [""; 0]);
+
+        // Another movie handed over under the tag ends the copy's use there.
+        let replaced = in_memory(&other, "tag-one");
+        assert_eq!(ask(0, &name, &replaced), [""; 0]);
+        assert_eq!(ask(3, &name, &one), [""; 0]);
+        assert_eq!(ask(3, &name, &two), served);
+    }
+}
diff -ruN -x target -x Cargo.lock -x '*.rej' -x .git a/crates/victory-game/src/prompts.rs b/crates/victory-game/src/prompts.rs
--- a/crates/victory-game/src/prompts.rs	1969-12-31 21:00:00.000000000 -0300
+++ b/crates/victory-game/src/prompts.rs	2026-11-27 19:10:52.008566300 -0300
@@ -0,0 +1,1100 @@
+//! Keyboard key caps in place of the title's gamepad button pictures.
+//!
+//! The title draws a control's prompt as an icon of one UI movie, picked by
+//! an icon number, and has icons for gamepad controls only. [`key_caps`]
+//! redraws that movie: each icon becomes the key that the keyboard's stand-in
+//! gamepad binds to the icon's control. [`hook`] hands the redrawn movie to
+//! the title. The movie is recognised by its structure, and nothing of it is
+//! kept here. Prompts do not follow rebinding or a device change, and the
+//! title's animated prompts keep their own pictures.
+
+use std::collections::{HashMap, HashSet};
+
+use victory_core::pad::{
+    PadControl, VK_BACK, VK_DOWN, VK_ESCAPE, VK_LBUTTON, VK_LCONTROL, VK_LEFT, VK_RBUTTON,
+    VK_RETURN, VK_RIGHT, VK_SPACE, VK_TAB, VK_UP, shown_key,
+};
+use victory_formats::gfx::{
+    self, Change, Contour, Depth, Edge, Movie, Placement, Point, ShapeBody, Sprite,
+};
+
+#[cfg(windows)]
+mod font;
+#[cfg(windows)]
+pub mod hook;
+
+/// An offset from an image's base to an 8-byte pointer.
+#[derive(Debug, Clone, Copy)]
+pub struct PointerOffset(pub u32);
+
+/// An offset from an image's base to a function's first instruction.
+#[derive(Debug, Clone, Copy)]
+pub struct CodeOffset(pub u32);
+
+/// Where a build keeps what the hook needs.
+#[derive(Debug, Clone, Copy)]
+pub struct HookOffsets {
+    /// The pointer through which the UI runtime calls the function that
+    /// builds a movie's address from a request.
+    pub movie_address_builder: PointerOffset,
+    /// The function that assigns C text to a UI runtime string.
+    pub string_assign: CodeOffset,
+}
+
+/// The icon numbers and the gamepad controls each one pictures: the
+/// numbers in the class names of the icon movie's sprites (Series 1.0.2.1),
+/// matched to the pictures the title's own icons show.
+const ICONS: &[(u32, &[PadControl])] = {
+    use PadControl as C;
+    const LEFT: &[PadControl] = &[
+        C::LeftStickUp,
+        C::LeftStickLeft,
+        C::LeftStickDown,
+        C::LeftStickRight,
+    ];
+    const RIGHT: &[PadControl] = &[
+        C::RightStickUp,
+        C::RightStickLeft,
+        C::RightStickDown,
+        C::RightStickRight,
+    ];
+    const PAD: &[PadControl] = &[C::Up, C::Down, C::Left, C::Right];
+    &[
+        (4, &[C::Up]),
+        (5, &[C::Down]),
+        (6, &[C::Left]),
+        (7, &[C::Right]),
+        (8, PAD),
+        (9, PAD),
+        (10, &[C::Up, C::Down]),
+        (11, &[C::Left, C::Right]),
+        (12, &[C::LeftStickUp]),
+        (13, &[C::LeftStickDown]),
+        (14, &[C::LeftStickLeft]),
+        (15, &[C::LeftStickRight]),
+        (16, &[C::LeftStick]),
+        (17, LEFT),
+        (18, &[C::LeftStickUp, C::LeftStickDown]),
+        (19, &[C::LeftStickLeft, C::LeftStickRight]),
+        (20, LEFT),
+        (21, &[C::RightStickUp]),
+        (22, &[C::RightStickDown]),
+        (23, &[C::RightStickLeft]),
+        (24, &[C::RightStickRight]),
+        (25, &[C::RightStick]),
+        (26, RIGHT),
+        (27, &[C::RightStickUp, C::RightStickDown]),
+        (28, &[C::RightStickLeft, C::RightStickRight]),
+        (29, RIGHT),
+        (30, &[C::A]),
+        (31, &[C::B]),
+        (32, &[C::X]),
+        (33, &[C::Y]),
+        (34, &[C::LeftShoulder]),
+        (35, &[C::LeftTrigger]),
+        (36, &[C::RightShoulder]),
+        (37, &[C::RightTrigger]),
+        (38, &[C::Menu]),
+        (39, &[C::View]),
+        (58, LEFT),
+        (59, RIGHT),
+    ]
+};
+
+/// A movie with fewer icons than this is not the icon movie.
+const FEWEST_ICONS: usize = 20;
+/// Controls whose icons the icon movie has besides.
+const FACE_BUTTONS: [PadControl; 4] = [PadControl::A, PadControl::B, PadControl::X, PadControl::Y];
+
+/// One icon cell: 64 pixels of 20 twips, the size of the title's own icon
+/// pictures (Series 1.0.2.1).
+const CELL_TWIPS: i32 = 1280;
+/// The cap's distance from the cell's edge and its corner radius.
+const CAP_MARGIN_TWIPS: i32 = 50;
+const CAP_RADIUS_TWIPS: i32 = 220;
+/// The label's distance from the cell's edge.
+const LABEL_MARGIN_TWIPS: i32 = 250;
+/// The tallest a row of a label is drawn: half the cell, so that a letter
+/// and a sign of one key are drawn the same height.
+const TALLEST_ROW_TWIPS: f64 = 640.0;
+/// The distance between a label's two rows, in ems.
+const ROW_EMS: f64 = 1.05;
+
+const WHITE: [u8; 4] = [0xFF; 4];
+const BLACK: [u8; 4] = [0, 0, 0, 0xFF];
+
+/// A position in ems, x right; y up from the baseline in a glyph, down from
+/// the first row's baseline once placed in a label.
+pub(crate) type EmPoint = [f64; 2];
+
+/// A character's outline, outer contours clockwise, and how far the pen
+/// moves after it.
+#[derive(Clone, Debug, PartialEq)]
+pub(crate) struct Glyph {
+    pub(crate) contours: Vec<Contour<EmPoint>>,
+    pub(crate) advance_ems: f64,
+}
+
+/// What a key cap shows for a virtual key; `None` for a key without one.
+fn key_label(virtual_key: u8) -> Option<&'static str> {
+    const LETTERS: &str = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
+    Some(match virtual_key {
+        // Written out, as GTA V and Red Dead Redemption 2 on PC show them.
+        VK_BACK => "Back",
+        VK_TAB => "Tab",
+        VK_RETURN => "Enter",
+        VK_ESCAPE => "Esc",
+        VK_LEFT => "\u{2190}",
+        VK_UP => "\u{2191}",
+        VK_RIGHT => "\u{2192}",
+        VK_DOWN => "\u{2193}",
+        VK_SPACE => "Space",
+        VK_LCONTROL => "Ctrl",
+        VK_LBUTTON => "LMB",
+        VK_RBUTTON => "RMB",
+        b'A'..=b'Z' => {
+            let at = usize::from(virtual_key - b'A');
+            LETTERS.get(at..=at)?
+        }
+        _ => return None,
+    })
+}
+
+/// The key cap: a rounded square, clockwise.
+fn cap() -> Contour {
+    let (low, high) = (CAP_MARGIN_TWIPS, CELL_TWIPS - CAP_MARGIN_TWIPS);
+    let (near, far) = (low + CAP_RADIUS_TWIPS, high - CAP_RADIUS_TWIPS);
+    let point = |x, y| Point { x, y };
+    let corner = |cx, cy, x, y| Edge::Curve {
+        control: point(cx, cy),
+        to: point(x, y),
+    };
+    Contour {
+        start: point(near, low),
+        edges: vec![
+            Edge::Line(point(far, low)),
+            corner(high, low, high, near),
+            Edge::Line(point(high, far)),
+            corner(high, high, far, high),
+            Edge::Line(point(near, high)),
+            corner(low, high, low, far),
+            Edge::Line(point(low, near)),
+            corner(low, low, near, low),
+        ],
+    }
+}
+
+/// A rounded rectangle from (`x0`, `y0`) to (`x1`, `y1`) with corner radius
+/// `r`; clockwise on screen (y down) when `clockwise`, else the other way
+/// round, which cuts a hole out of a clockwise contour around it.
+fn rounded(x0: i32, y0: i32, x1: i32, y1: i32, r: i32, clockwise: bool) -> Contour {
+    let point = |x, y| Point { x, y };
+    let corner = |cx, cy, x, y| Edge::Curve {
+        control: point(cx, cy),
+        to: point(x, y),
+    };
+    if clockwise {
+        Contour {
+            start: point(x0 + r, y0),
+            edges: vec![
+                Edge::Line(point(x1 - r, y0)),
+                corner(x1, y0, x1, y0 + r),
+                Edge::Line(point(x1, y1 - r)),
+                corner(x1, y1, x1 - r, y1),
+                Edge::Line(point(x0 + r, y1)),
+                corner(x0, y1, x0, y1 - r),
+                Edge::Line(point(x0, y0 + r)),
+                corner(x0, y0, x0 + r, y0),
+            ],
+        }
+    } else {
+        Contour {
+            start: point(x0 + r, y0),
+            edges: vec![
+                corner(x0, y0, x0, y0 + r),
+                Edge::Line(point(x0, y1 - r)),
+                corner(x0, y1, x0 + r, y1),
+                Edge::Line(point(x1 - r, y1)),
+                corner(x1, y1, x1, y1 - r),
+                Edge::Line(point(x1, y0 + r)),
+                corner(x1, y0, x1 - r, y0),
+                Edge::Line(point(x0 + r, y0)),
+            ],
+        }
+    }
+}
+
+/// A plain rectangle, clockwise on screen.
+fn rect(x0: i32, y0: i32, x1: i32, y1: i32) -> Contour {
+    let point = |x, y| Point { x, y };
+    Contour {
+        start: point(x0, y0),
+        edges: vec![
+            Edge::Line(point(x1, y0)),
+            Edge::Line(point(x1, y1)),
+            Edge::Line(point(x0, y1)),
+            Edge::Line(point(x0, y0)),
+        ],
+    }
+}
+
+/// The picture GTA V and Red Dead Redemption 2 on PC show for a mouse
+/// button, drawn in the label's colour over the cap: a mouse outline, the
+/// line between its buttons, and the button meant (`left`) filled in.
+fn mouse(left: bool) -> Vec<Contour> {
+    const X0: i32 = 390;
+    const X1: i32 = CELL_TWIPS - 390;
+    const Y0: i32 = 230;
+    const Y1: i32 = CELL_TWIPS - 230;
+    const WALL: i32 = 70;
+    const MID_X: i32 = CELL_TWIPS / 2;
+    const SPLIT_Y: i32 = 600;
+    let (ix0, ix1, iy0, iy1) = (X0 + WALL, X1 - WALL, Y0 + WALL, Y1 - WALL);
+    let half = WALL / 2;
+    let button = if left {
+        rect(ix0, iy0, MID_X - half, SPLIT_Y - half)
+    } else {
+        rect(MID_X + half, iy0, ix1, SPLIT_Y - half)
+    };
+    vec![
+        // The outline: the body, with its inside cut out.
+        rounded(X0, Y0, X1, Y1, 250, true),
+        rounded(ix0, iy0, ix1, iy1, 250 - WALL, false),
+        // The line between the buttons and the one under them.
+        rect(MID_X - half, iy0, MID_X + half, SPLIT_Y + half),
+        rect(ix0, SPLIT_Y - half, ix1, SPLIT_Y + half),
+        button,
+    ]
+}
+
+/// The mouse button a single control is shown as in the GTA layout, if any:
+/// `Some(true)` for the left one.
+fn mouse_button(controls: &[PadControl]) -> Option<bool> {
+    match controls {
+        [control] => match shown_key(*control) {
+            VK_LBUTTON => Some(true),
+            VK_RBUTTON => Some(false),
+            _ => None,
+        },
+        _ => None,
+    }
+}
+
+/// The labels of `keys` placed in the cell, from `glyphs`: in one row, or
+/// in two rows of two keys for four. `None` when a character has no glyph.
+fn label(keys: &[&str], glyphs: &HashMap<char, Glyph>) -> Option<Vec<Contour>> {
+    let rows: Vec<String> = if keys.len() == 4 {
+        keys.chunks(2).map(<[&str]>::concat).collect()
+    } else {
+        vec![keys.concat()]
+    };
+    // Each row's contours, x from the row's start, y down from the first
+    // row's baseline.
+    let mut placed: Vec<Vec<Contour<EmPoint>>> = Vec::new();
+    let mut down = 0.0;
+    for row in rows {
+        let mut contours = Vec::new();
+        let mut pen = 0.0;
+        for character in row.chars() {
+            let glyph = glyphs.get(&character)?;
+            let place = |[x, y]: EmPoint| [x + pen, down - y];
+            contours.extend(glyph.contours.iter().map(|contour| contour.map(place)));
+            pen += glyph.advance_ems;
+        }
+        placed.push(contours);
+        down += ROW_EMS;
+    }
+    let extent = |contours: &[Contour<EmPoint>], axis: usize| {
+        contours
+            .iter()
+            .flat_map(Contour::points)
+            .fold((f64::MAX, f64::MIN), |(low, high), point| {
+                (low.min(point[axis]), high.max(point[axis]))
+            })
+    };
+    let widths: Vec<(f64, f64)> = placed.iter().map(|row| extent(row, 0)).collect();
+    let heights: Vec<(f64, f64)> = placed.iter().map(|row| extent(row, 1)).collect();
+    let widest = widths
+        .iter()
+        .map(|(low, high)| high - low)
+        .fold(0.0, f64::max);
+    let tallest_row = heights
+        .iter()
+        .map(|(low, high)| high - low)
+        .fold(0.0, f64::max);
+    let (top, bottom) = heights
+        .iter()
+        .fold((f64::MAX, f64::MIN), |(low, high), &(a, b)| {
+            (low.min(a), high.max(b))
+        });
+    if !(widest > 0.0 && tallest_row > 0.0) {
+        return None;
+    }
+    let room = f64::from(CELL_TWIPS - 2 * LABEL_MARGIN_TWIPS);
+    let scale = (room / widest)
+        .min(room / (bottom - top))
+        .min(TALLEST_ROW_TWIPS / tallest_row);
+    let middle = f64::from(CELL_TWIPS) / 2.0;
+    let mut contours = Vec::new();
+    for (row, (low, high)) in placed.iter().zip(&widths) {
+        // Inside the cell by construction, so the conversion keeps the value.
+        #[expect(
+            clippy::cast_possible_truncation,
+            reason = "a position inside one icon cell"
+        )]
+        let twips = |[x, y]: EmPoint| Point {
+            x: (middle + (x - (low + high) / 2.0) * scale).round() as i32,
+            y: (middle + (y - (top + bottom) / 2.0) * scale).round() as i32,
+        };
+        contours.extend(row.iter().map(|contour| contour.map(twips)));
+    }
+    Some(contours)
+}
+
+/// The icon number a class name ends in, after its last `_`.
+fn icon_number(name: &[u8]) -> Option<u32> {
+    let digits = name.get(name.iter().rposition(|&byte| byte == b'_')? + 1..)?;
+    if digits.is_empty() || !digits.iter().all(u8::is_ascii_digit) {
+        return None;
+    }
+    std::str::from_utf8(digits).ok()?.parse().ok()
+}
+
+/// The shapes a sprite places, back to front, when it is one still frame of
+/// placements; `None` when it changes over time or masks.
+fn still_shapes(sprite: &Sprite) -> Option<Vec<u16>> {
+    let mut placed: Vec<(Depth, u16)> = sprite
+        .placements
+        .iter()
+        .map(|placement| match placement.change {
+            Change::Place(character) if placement.frame == 0 => Some((placement.depth, character)),
+            Change::Place(_)
+            | Change::Mask(_)
+            | Change::Replace(_)
+            | Change::Modify
+            | Change::Remove
+            | Change::Unread => None,
+        })
+        .collect::<Option<_>>()?;
+    placed.sort_unstable();
+    if placed.windows(2).any(|pair| pair[0].0 == pair[1].0) {
+        return None;
+    }
+    Some(placed.into_iter().map(|(_, shape)| shape).collect())
+}
+
+/// The controls an icon number pictures.
+fn controls(number: u32) -> Option<&'static [PadControl]> {
+    ICONS
+        .iter()
+        .find(|(known, _)| *known == number)
+        .map(|(_, controls)| *controls)
+}
+
+/// How many times each character is placed, anywhere in a movie. `None`
+/// when a placement does not say what it places.
+fn uses(sprites: &[Sprite], timeline: &[Placement]) -> Option<HashMap<u16, u32>> {
+    let mut uses = HashMap::new();
+    let placements = sprites
+        .iter()
+        .flat_map(|sprite| &sprite.placements)
+        .chain(timeline);
+    for placement in placements {
+        match placement.change {
+            Change::Place(character) | Change::Mask(character) | Change::Replace(character) => {
+                *uses.entry(character).or_insert(0) += 1;
+            }
+            Change::Modify | Change::Remove => {}
+            Change::Unread => return None,
+        }
+    }
+    Some(uses)
+}
+
+/// Why a movie was not redrawn.
+#[derive(Clone, Copy, Debug, PartialEq, Eq)]
+pub(crate) enum Refusal {
+    /// It is not the icon movie.
+    NotIconMovie,
+    /// It is the icon movie, but it places something this module cannot read.
+    Unreadable,
+    /// It is the icon movie, but no icon of it could be drawn: a glyph is
+    /// missing, or a shape is drawn elsewhere too.
+    NothingDrawn,
+}
+
+/// `movie` with each known icon drawn as a key cap, labelled with `glyph`'s
+/// outlines.
+#[cfg_attr(
+    not(any(windows, test)),
+    expect(dead_code, reason = "only the Windows hook draws key caps")
+)]
+pub(crate) fn key_caps(
+    movie: &[u8],
+    glyph: &dyn Fn(char) -> Option<Glyph>,
+) -> Result<Vec<u8>, Refusal> {
+    let movie = Movie::parse(movie).ok_or(Refusal::NotIconMovie)?;
+    // The class table first: it alone tells most movies apart. The first
+    // class of each known number names that icon's sprite.
+    let mut numbers = HashSet::new();
+    let mut wanted: HashMap<u16, &'static [PadControl]> = HashMap::new();
+    for (sprite, name) in movie.classes().ok_or(Refusal::NotIconMovie)? {
+        let Some((number, controls)) = icon_number(name).and_then(|n| Some((n, controls(n)?)))
+        else {
+            continue;
+        };
+        if numbers.insert(number) {
+            wanted.entry(sprite).or_insert(controls);
+        }
+    }
+    let has_icon = |button: PadControl| {
+        ICONS
+            .iter()
+            .any(|&(number, controls)| controls == [button] && numbers.contains(&number))
+    };
+    if numbers.len() < FEWEST_ICONS || !FACE_BUTTONS.into_iter().all(has_icon) {
+        return Err(Refusal::NotIconMovie);
+    }
+    if movie.defines_buttons() {
+        return Err(Refusal::Unreadable);
+    }
+    let sprites = movie.sprites().ok_or(Refusal::Unreadable)?;
+    let timeline = movie.timeline().ok_or(Refusal::Unreadable)?;
+    let uses = uses(&sprites, &timeline).ok_or(Refusal::Unreadable)?;
+    let icons: Vec<(&[PadControl], Vec<u16>)> = sprites
+        .iter()
+        .filter_map(|sprite| Some((wanted.remove(&sprite.id)?, still_shapes(sprite)?)))
+        .collect();
+    if icons.iter().filter(|(_, shapes)| shapes.len() >= 2).count() < FEWEST_ICONS {
+        return Err(Refusal::NotIconMovie);
+    }
+    let definitions = movie.shape_counts();
+    let keys_of = |controls: &[PadControl]| {
+        controls
+            .iter()
+            .map(|&control| key_label(shown_key(control)))
+            .collect::<Option<Vec<_>>>()
+    };
+    // The font is asked for each character once.
+    let mut asked = HashSet::new();
+    let mut glyphs: HashMap<char, Glyph> = HashMap::new();
+    for character in icons
+        .iter()
+        .filter_map(|(controls, _)| keys_of(controls))
+        .flatten()
+        .flat_map(str::chars)
+    {
+        if asked.insert(character)
+            && let Some(found) = glyph(character)
+        {
+            glyphs.insert(character, found);
+        }
+    }
+    let mut bodies: Vec<ShapeBody> = Vec::new();
+    for (controls, shapes) in &icons {
+        // The back shape becomes the cap, the next one the label, and any
+        // further ones nothing. An icon keeps its picture when a shape of it
+        // is drawn elsewhere too, or is not one shape this module writes.
+        let [back, front, rest @ ..] = shapes.as_slice() else {
+            continue;
+        };
+        if shapes
+            .iter()
+            .any(|shape| uses.get(shape) != Some(&1) || definitions.get(shape) != Some(&1))
+        {
+            continue;
+        }
+        let Some(keys) = keys_of(controls) else {
+            continue;
+        };
+        let drawn = match mouse_button(controls) {
+            Some(left) => Some(mouse(left)),
+            None => label(&keys, &glyphs),
+        };
+        let Some(label) = drawn.and_then(|label| gfx::shape(*front, BLACK, &label)) else {
+            continue;
+        };
+        // Fill style 0, as the title's own shapes have it: with the cap's
+        // colour as style 1, the first screen stayed black in one run.
+        bodies.push(gfx::shape(*back, WHITE, &[cap()]).ok_or(Refusal::Unreadable)?);
+        bodies.push(label);
+        for &shape in rest {
+            bodies.push(gfx::shape(shape, BLACK, &[]).ok_or(Refusal::Unreadable)?);
+        }
+    }
+    if bodies.is_empty() {
+        return Err(Refusal::NothingDrawn);
+    }
+    movie.replace_shapes(&bodies).ok_or(Refusal::Unreadable)
+}
+
+/// Hand-built movies for the tests of this module and of [`hook`].
+#[cfg(test)]
+pub(crate) mod fixtures {
+    use super::ICONS;
+
+    pub(crate) const END: u16 = 0;
+    pub(crate) const SHOW_FRAME: u16 = 1;
+    pub(crate) const PLACE_OBJECT_2: u16 = 26;
+    pub(crate) const DEFINE_SHAPE_3: u16 = 32;
+    pub(crate) const DEFINE_SPRITE: u16 = 39;
+    pub(crate) const PLACE_OBJECT_3: u16 = 70;
+    pub(crate) const SYMBOL_CLASS: u16 = 76;
+
+    /// The first sprite id the fixtures give.
+    pub(crate) const FIRST_SPRITE: u16 = 60_000;
+
+    pub(crate) fn tag(code: u16, body: &[u8]) -> Vec<u8> {
+        let mut bytes = ((code << 6) | 0x3F).to_le_bytes().to_vec();
+        bytes.extend(u32::try_from(body.len()).unwrap().to_le_bytes());
+        bytes.extend(body);
+        bytes
+    }
+
+    /// A placement of `shape` at `depth`, with a matrix.
+    pub(crate) fn place(depth: u16, shape: u16) -> Vec<u8> {
+        let mut body = vec![0b110];
+        body.extend(depth.to_le_bytes());
+        body.extend(shape.to_le_bytes());
+        tag(PLACE_OBJECT_2, &body)
+    }
+
+    /// A placement of `shape` at `depth` as a mask over deeper ones.
+    pub(crate) fn mask(depth: u16, shape: u16) -> Vec<u8> {
+        let mut body = vec![0x46];
+        body.extend(depth.to_le_bytes());
+        body.extend(shape.to_le_bytes());
+        tag(PLACE_OBJECT_2, &body)
+    }
+
+    /// The body a hand-built movie gives the shape `id`.
+    pub(crate) fn picture(id: u16) -> Vec<u8> {
+        [id.to_le_bytes(), [0xAB, 0xCD]].concat()
+    }
+
+    /// A movie of `shapes`, then sprites of their own tags, then a class
+    /// table naming characters.
+    pub(crate) fn movie(
+        shapes: &[u16],
+        sprites: &[(u16, Vec<Vec<u8>>)],
+        classes: &[(u16, String)],
+    ) -> Vec<u8> {
+        let mut bytes = b"GFX\x0b\0\0\0\0\0\0\x1e\x01\0".to_vec();
+        for &shape in shapes {
+            bytes.extend(tag(DEFINE_SHAPE_3, &picture(shape)));
+        }
+        for (id, own) in sprites {
+            let mut body = [id.to_le_bytes(), [0, 0]].concat();
+            body.extend(own.concat());
+            body.extend(tag(END, &[]));
+            bytes.extend(tag(DEFINE_SPRITE, &body));
+        }
+        let mut table = u16::try_from(classes.len()).unwrap().to_le_bytes().to_vec();
+        for (id, name) in classes {
+            table.extend(id.to_le_bytes());
+            table.extend(name.bytes());
+            table.push(0);
+        }
+        bytes.extend(tag(SYMBOL_CLASS, &table));
+        bytes.extend(tag(END, &[]));
+        let len = u32::try_from(bytes.len()).unwrap().to_le_bytes();
+        bytes[4..8].copy_from_slice(&len);
+        bytes
+    }
+
+    /// Every known icon with three shapes of its own, placed back to
+    /// front: 100 times its number, and the two after it.
+    pub(crate) fn known_icons() -> Vec<(u32, Vec<u16>)> {
+        ICONS
+            .iter()
+            .map(|&(number, _)| {
+                let first = 100 * u16::try_from(number).unwrap();
+                (number, vec![first, first + 1, first + 2])
+            })
+            .collect()
+    }
+
+    /// The parts of a movie, for a test to change before it is built.
+    pub(crate) struct Parts {
+        pub(crate) shapes: Vec<u16>,
+        pub(crate) sprites: Vec<(u16, Vec<Vec<u8>>)>,
+        pub(crate) classes: Vec<(u16, String)>,
+    }
+
+    impl Parts {
+        pub(crate) fn movie(&self) -> Vec<u8> {
+            movie(&self.shapes, &self.sprites, &self.classes)
+        }
+    }
+
+    /// The parts of a movie of `icons`, each a sprite placing its shapes at
+    /// depths 1, 2 and so on, with a class named for its number.
+    pub(crate) fn parts(icons: &[(u32, Vec<u16>)]) -> Parts {
+        let mut shapes: Vec<u16> = icons
+            .iter()
+            .flat_map(|(_, shapes)| shapes.clone())
+            .collect();
+        shapes.sort_unstable();
+        shapes.dedup();
+        let sprite = |index: usize| FIRST_SPRITE + u16::try_from(index).unwrap();
+        let sprites = icons
+            .iter()
+            .enumerate()
+            .map(|(index, (_, shapes))| {
+                let placed = (1..).zip(shapes).map(|(depth, &shape)| place(depth, shape));
+                (sprite(index), placed.collect())
+            })
+            .collect();
+        let classes = icons
+            .iter()
+            .enumerate()
+            .map(|(index, (number, _))| (sprite(index), format!("icon_{number}")))
+            .collect();
+        Parts {
+            shapes,
+            sprites,
+            classes,
+        }
+    }
+
+    pub(crate) fn icon_movie(icons: &[(u32, Vec<u16>)]) -> Vec<u8> {
+        parts(icons).movie()
+    }
+}
+
+#[cfg(test)]
+mod tests {
+    use std::cell::Cell;
+    use std::collections::HashMap;
+    use std::time::{Duration, Instant};
+
+    use victory_core::pad::{PadControl, VK_BACK, VK_RETURN, fallback_key};
+    use victory_formats::gfx::{Contour, Edge, Point};
+
+    use super::fixtures::{
+        DEFINE_SHAPE_3, PLACE_OBJECT_3, SHOW_FRAME, icon_movie, known_icons, mask, parts, picture,
+        place, tag,
+    };
+    use super::{Glyph, ICONS, Refusal, controls, icon_number, key_caps, key_label, label};
+
+    /// A square half an em wide on the baseline, clockwise with y up.
+    fn square(_: char) -> Option<Glyph> {
+        Some(Glyph {
+            contours: vec![Contour {
+                start: [0.0, 0.0],
+                edges: [[0.0, 0.5], [0.5, 0.5], [0.5, 0.0], [0.0, 0.0]]
+                    .map(Edge::Line)
+                    .to_vec(),
+            }],
+            advance_ems: 0.6,
+        })
+    }
+
+    /// A square glyph for each character of `text`.
+    fn squares(text: &str) -> HashMap<char, Glyph> {
+        text.chars()
+            .filter_map(|character| Some((character, square(character)?)))
+            .collect()
+    }
+
+    /// `movie` with `tag` as its first tag, after its 13-byte header.
+    fn with_first_tag(movie: &[u8], tag: &[u8]) -> Vec<u8> {
+        let mut bytes = [&movie[..13], tag, &movie[13..]].concat();
+        let len = u32::try_from(bytes.len()).unwrap().to_le_bytes();
+        bytes[4..8].copy_from_slice(&len);
+        bytes
+    }
+
+    /// The tags of a fixture movie (all with long headers) after its
+    /// 13-byte header: code and body.
+    fn fixture_tags(movie: &[u8]) -> Vec<(u16, &[u8])> {
+        let mut found = Vec::new();
+        let mut at = 13;
+        while at < movie.len() {
+            let code = u16::from_le_bytes([movie[at], movie[at + 1]]) >> 6;
+            let len = u32::from_le_bytes(movie[at + 2..at + 6].try_into().unwrap());
+            let end = at + 6 + usize::try_from(len).unwrap();
+            found.push((code, &movie[at + 6..end]));
+            at = end;
+        }
+        found
+    }
+
+    /// The body of each shape tag of a fixture movie, by the shape's id.
+    fn shape_bodies(movie: &[u8]) -> Vec<(u16, &[u8])> {
+        fixture_tags(movie)
+            .into_iter()
+            .filter(|&(code, _)| code == DEFINE_SHAPE_3)
+            .map(|(_, body)| (u16::from_le_bytes([body[0], body[1]]), body))
+            .collect()
+    }
+
+    /// The fill a written shape has, after its id and 7 bytes of bounds.
+    fn fill(body: &[u8]) -> &[u8] {
+        &body[9..17]
+    }
+
+    const WHITE_FILL: [u8; 8] = [1, 0, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0x10];
+    const BLACK_FILL: [u8; 8] = [1, 0, 0, 0, 0, 0xFF, 0, 0x10];
+
+    /// Checks that the shapes `redrawn` names were drawn anew and every
+    /// other shape kept the fixtures' picture.
+    fn redrawn_only(movie: &[u8], redrawn: impl Fn(u16) -> bool) {
+        for (id, body) in shape_bodies(movie) {
+            assert_eq!(body != picture(id), redrawn(id), "{id}");
+        }
+    }
+
+    #[test]
+    fn every_known_icon_becomes_a_white_cap_under_a_black_label() {
+        let mut icons = known_icons();
+        // An icon whose number is not a gamepad control keeps its picture.
+        icons.push((3, vec![1, 2]));
+        let original = icon_movie(&icons);
+
+        let redrawn = key_caps(&original, &square).unwrap();
+
+        let bodies = shape_bodies(&redrawn);
+        assert_eq!(bodies.len(), 3 * ICONS.len() + 2);
+        for (id, body) in bodies {
+            let empty = [
+                &id.to_le_bytes()[..],
+                &[0x08, 0x00, 1, 0, 0, 0, 0, 0xFF, 0, 0x10, 0x00],
+            ]
+            .concat();
+            match (id < 100, id % 100) {
+                (true, _) => assert_eq!(body, picture(id), "{id}"),
+                (false, 0) => assert_eq!(fill(body), WHITE_FILL, "{id}"),
+                (false, 1) => assert_eq!(fill(body), BLACK_FILL, "{id}"),
+                (false, _) => assert_eq!(body, empty, "{id}"),
+            }
+        }
+        assert_eq!(
+            redrawn[4..8],
+            u32::try_from(redrawn.len()).unwrap().to_le_bytes()
+        );
+        // Sprites, classes and the end tag are as they were.
+        let others = |movie| {
+            fixture_tags(movie)
+                .into_iter()
+                .filter(|&(code, _)| code != DEFINE_SHAPE_3)
+                .map(|(code, body)| (code, body.to_vec()))
+                .collect::<Vec<_>>()
+        };
+        assert_eq!(others(&redrawn), others(&original));
+    }
+
+    #[test]
+    fn a_movie_with_few_known_icons_is_not_the_icon_movie() {
+        // 19 known numbers, the face buttons among them.
+        let mut icons = known_icons();
+        icons.retain(|&(number, _)| number >= 21);
+        icons.truncate(19);
+        icons.push((3, vec![1, 2]));
+
+        assert_eq!(
+            key_caps(&icon_movie(&icons), &square),
+            Err(Refusal::NotIconMovie)
+        );
+        assert_eq!(key_caps(b"GFX", &square), Err(Refusal::NotIconMovie));
+    }
+
+    #[test]
+    fn a_movie_with_few_icons_of_two_shapes_is_not_the_icon_movie() {
+        // Every number is known, but each icon is a single shape.
+        let icons: Vec<(u32, Vec<u16>)> = known_icons()
+            .into_iter()
+            .map(|(number, shapes)| (number, shapes[..1].to_vec()))
+            .collect();
+
+        assert_eq!(
+            key_caps(&icon_movie(&icons), &square),
+            Err(Refusal::NotIconMovie)
+        );
+    }
+
+    #[test]
+    fn a_movie_with_a_button_leaves_its_icons_alone() {
+        // A button's records name characters too.
+        let button = tag(34, &[1, 0, 0, 0, 0, 0]);
+        let movie = with_first_tag(&icon_movie(&known_icons()), &button);
+
+        assert_eq!(key_caps(&movie, &square), Err(Refusal::Unreadable));
+    }
+
+    #[test]
+    fn a_movie_without_the_face_buttons_is_not_the_icon_movie() {
+        let mut icons = known_icons();
+        icons.retain(|&(number, _)| number != 33);
+
+        assert_eq!(
+            key_caps(&icon_movie(&icons), &square),
+            Err(Refusal::NotIconMovie)
+        );
+    }
+
+    #[test]
+    fn a_movie_where_no_icon_can_be_drawn_is_left_alone() {
+        assert_eq!(
+            key_caps(&icon_movie(&known_icons()), &|_| None),
+            Err(Refusal::NothingDrawn)
+        );
+    }
+
+    #[test]
+    fn many_classes_and_sprites_are_looked_up_once_each() {
+        // Classes that each named every sprite would take minutes here.
+        let mut parts = parts(&known_icons());
+        for id in 1..=59_999u16 {
+            parts.classes.push((id, "extra_4".to_owned()));
+            parts.sprites.push((id, Vec::new()));
+        }
+
+        let movie = parts.movie();
+
+        let started = Instant::now();
+        let redrawn = key_caps(&movie, &square);
+
+        assert!(redrawn.is_ok());
+        assert!(
+            started.elapsed() < Duration::from_secs(2),
+            "{:?}",
+            started.elapsed()
+        );
+    }
+
+    #[test]
+    fn an_icon_that_shares_a_shape_with_any_sprite_keeps_its_picture() {
+        let mut parts = parts(&known_icons());
+        // A sprite with no class draws icon 4's back shape too.
+        parts.sprites.push((100, vec![place(1, 400)]));
+
+        let redrawn = key_caps(&parts.movie(), &square).unwrap();
+
+        redrawn_only(&redrawn, |id| id / 100 != 4);
+    }
+
+    #[test]
+    fn an_icon_placing_something_other_than_a_shape_keeps_its_picture() {
+        let mut parts = parts(&known_icons());
+        // Icon 4's label is no shape of the movie.
+        parts.shapes.retain(|&shape| shape != 401);
+
+        let redrawn = key_caps(&parts.movie(), &square).unwrap();
+
+        redrawn_only(&redrawn, |id| id / 100 != 4);
+    }
+
+    #[test]
+    fn an_icon_whose_shape_is_defined_twice_keeps_its_picture() {
+        let mut parts = parts(&known_icons());
+        parts.shapes.push(400);
+
+        let redrawn = key_caps(&parts.movie(), &square).unwrap();
+
+        redrawn_only(&redrawn, |id| id / 100 != 4);
+    }
+
+    #[test]
+    fn an_icon_with_a_mask_keeps_its_picture() {
+        let mut parts = parts(&known_icons());
+        parts.sprites[0].1[2] = mask(3, 402);
+
+        let redrawn = key_caps(&parts.movie(), &square).unwrap();
+
+        redrawn_only(&redrawn, |id| id / 100 != 4);
+    }
+
+    #[test]
+    fn the_back_shape_is_found_by_depth_not_by_tag_order_or_id() {
+        let icons = known_icons();
+        let mut parts = parts(&icons);
+        // Every icon places its shapes in id order, at depths 3, 2 and 1.
+        for ((_, own), (_, shapes)) in parts.sprites.iter_mut().zip(&icons) {
+            *own = (1..=3)
+                .rev()
+                .zip(shapes)
+                .map(|(depth, &shape)| place(depth, shape))
+                .collect();
+        }
+
+        let redrawn = key_caps(&parts.movie(), &square).unwrap();
+
+        for (id, body) in shape_bodies(&redrawn) {
+            match id % 100 {
+                2 => assert_eq!(fill(body), WHITE_FILL, "{id}"),
+                1 => assert_eq!(fill(body), BLACK_FILL, "{id}"),
+                _ => assert_eq!(body.len(), 13, "{id}"),
+            }
+        }
+    }
+
+    #[test]
+    fn an_icon_that_changes_over_frames_keeps_its_picture() {
+        let mut parts = parts(&known_icons());
+        // Icon 4 places its last shape in a second frame.
+        parts.sprites[0].1.insert(2, tag(SHOW_FRAME, &[]));
+
+        let redrawn = key_caps(&parts.movie(), &square).unwrap();
+
+        redrawn_only(&redrawn, |id| id / 100 != 4);
+    }
+
+    #[test]
+    fn a_placement_that_cannot_be_read_leaves_the_movie_alone() {
+        let mut parts = parts(&known_icons());
+        parts
+            .sprites
+            .push((100, vec![tag(PLACE_OBJECT_3, &[0, 0, 1, 0])]));
+
+        assert_eq!(key_caps(&parts.movie(), &square), Err(Refusal::Unreadable));
+    }
+
+    #[test]
+    fn a_second_icon_with_a_number_keeps_its_picture() {
+        let mut icons = known_icons();
+        icons.push((30, vec![1, 2]));
+
+        let redrawn = key_caps(&icon_movie(&icons), &square).unwrap();
+
+        redrawn_only(&redrawn, |id| id >= 100);
+    }
+
+    #[test]
+    fn an_icon_whose_key_has_no_glyph_keeps_its_picture() {
+        let no_arrows = |character: char| {
+            if ('\u{2190}'..='\u{2193}').contains(&character) {
+                None
+            } else {
+                square(character)
+            }
+        };
+
+        let redrawn = key_caps(&icon_movie(&known_icons()), &no_arrows).unwrap();
+
+        // Icons 4 to 11 are the direction pad's, on the arrow keys.
+        redrawn_only(&redrawn, |id| !(4..=11).contains(&(id / 100)));
+    }
+
+    #[test]
+    fn the_enter_key_labels_the_a_button_and_backspace_the_b_button() {
+        let only = |wanted: char| {
+            move |character: char| {
+                if character == wanted {
+                    square(character)
+                } else {
+                    None
+                }
+            }
+        };
+
+        // Written out, as GTA V and Red Dead Redemption 2 on PC show them;
+        // a key whose label lacks a glyph keeps its picture.
+        let _ = only;
+        assert_eq!(key_label(VK_RETURN), Some("Enter"));
+        assert_eq!(key_label(VK_BACK), Some("Back"));
+        assert_eq!(controls(30), Some(&[PadControl::A][..]));
+        assert_eq!(controls(31), Some(&[PadControl::B][..]));
+    }
+
+    #[test]
+    fn each_character_is_asked_for_once() {
+        let asked = Cell::new(0);
+        let counting = |character| {
+            asked.set(asked.get() + 1);
+            square(character)
+        };
+
+        key_caps(&icon_movie(&known_icons()), &counting).unwrap();
+
+        // Arrows 4, letters 16, "Esc" and "Tab" 5 more, "Enter" 4 and "Back" 2.
+        assert_eq!(asked.get(), 31);
+    }
+
+    #[test]
+    fn every_key_of_the_stand_in_pad_has_a_label() {
+        for control in ICONS.iter().flat_map(|(_, controls)| controls.iter()) {
+            assert!(key_label(fallback_key(*control)).is_some(), "{control:?}");
+        }
+        assert_eq!(key_label(0x1B), Some("Esc"));
+        assert_eq!(key_label(b'Q'), Some("Q"));
+        assert_eq!(key_label(0x70), None);
+    }
+
+    fn line(x: i32, y: i32) -> Edge {
+        Edge::Line(Point { x, y })
+    }
+
+    #[test]
+    fn one_character_is_centred_at_the_tallest_size() {
+        // Half an em drawn 640 twips tall, around the middle of a 1280-twip
+        // cell.
+        assert_eq!(
+            label(&["A"], &squares("A")),
+            Some(vec![Contour {
+                start: Point { x: 320, y: 960 },
+                edges: vec![
+                    line(320, 320),
+                    line(960, 320),
+                    line(960, 960),
+                    line(320, 960)
+                ],
+            }])
+        );
+    }
+
+    #[test]
+    fn four_keys_are_set_in_two_rows_inside_the_margin() {
+        let contours = label(&["A", "B", "C", "D"], &squares("ABCD")).unwrap();
+
+        // 1.55 ems of height fill the 780 twips between the margins.
+        let starts: Vec<Point> = contours.iter().map(|contour| contour.start).collect();
+        assert_eq!(
+            starts,
+            [
+                Point { x: 363, y: 502 },
+                Point { x: 665, y: 502 },
+                Point { x: 363, y: 1030 },
+                Point { x: 665, y: 1030 },
+            ]
+        );
+        assert_eq!(
+            contours[0].edges,
+            [
+                line(363, 250),
+                line(615, 250),
+                line(615, 502),
+                line(363, 502)
+            ]
+        );
+    }
+
+    #[test]
+    fn two_keys_of_four_characters_stay_in_one_row() {
+        let contours = label(&["Esc", "\u{21B5}"], &squares("Esc\u{21B5}")).unwrap();
+
+        assert_eq!(contours.len(), 4);
+        assert!(
+            contours
+                .iter()
+                .all(|contour| contour.start.y == contours[0].start.y)
+        );
+    }
+
+    #[test]
+    fn a_label_with_a_character_without_a_glyph_is_not_drawn() {
+        assert_eq!(label(&["A", "B"], &squares("A")), None);
+        assert_eq!(label(&[], &squares("A")), None);
+    }
+
+    #[test]
+    fn a_class_name_gives_the_number_after_its_last_underscore() {
+        assert_eq!(icon_number(b"icon_12"), Some(12));
+        assert_eq!(icon_number(b"a_b_7"), Some(7));
+        assert_eq!(icon_number(b"7"), None);
+        assert_eq!(icon_number(b"icon_"), None);
+        assert_eq!(icon_number(b"icon_1a"), None);
+        assert_eq!(icon_number(b""), None);
+        assert_eq!(icon_number(b"icon_99999999999"), None);
+    }
+}
diff -ruN -x target -x Cargo.lock -x '*.rej' -x .git a/crates/victory-gpu/src/host.rs b/crates/victory-gpu/src/host.rs
--- a/crates/victory-gpu/src/host.rs	2026-11-27 12:16:03.488877300 -0300
+++ b/crates/victory-gpu/src/host.rs	2026-11-27 20:18:06.927116600 -0300
@@ -708,14 +708,80 @@
 /// frame's time.
 fn card_clock_line(frames: f64, ms: f64) {
     let [idle, behind, stood] = [0, 1, 2].map(|i| CARD_CLOCK_US[i].swap(0, Ordering::Relaxed) as f64 / 1000.0 / frames);
+    let busy = if ms > 0.0 { (100.0 * (1.0 - idle / ms)).clamp(0.0, 100.0) } else { 0.0 };
+    CARD_BUSY_PERCENT.store(busy.round() as u64, Ordering::Relaxed);
     tracing::info!(
         "the card's clock per frame: nothing of ours queued {idle:.1} ms (the card about {:.0}% busy by this count), \
          {behind:.1} ms of that while the submitting thread was working (the card idle behind us), the rest while the title \
          had not submitted; the submitting thread stood waiting for the card {stood:.1} ms",
-        if ms > 0.0 { (100.0 * (1.0 - idle / ms)).clamp(0.0, 100.0) } else { 0.0 }
+        busy
     );
 }
 
+/// The card's share of the last second busy with our work ([`card_clock_line`]),
+/// for the window's caption.
+static CARD_BUSY_PERCENT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
+
+/// The window caption's measures beside the frame rate: the frame-rate mean of
+/// the world (frames of 500 draws or more; the whole run before the first),
+/// this process's RAM in use (GB) and its CPU use (percent of all cores).
+#[cfg(windows)]
+fn caption_measures(fps: f64, secs: f64, draws: f64) -> (f64, f64, f64) {
+    use std::sync::Mutex;
+    use windows_sys::Win32::Foundation::FILETIME;
+    use windows_sys::Win32::System::ProcessStatus::{GetProcessMemoryInfo, PROCESS_MEMORY_COUNTERS};
+    use windows_sys::Win32::System::Threading::{GetCurrentProcess, GetProcessTimes};
+    // (world frames, world seconds, all frames, all seconds)
+    static MEAN: Mutex<(f64, f64, f64, f64)> = Mutex::new((0.0, 0.0, 0.0, 0.0));
+    // (process CPU time in 100 ns, wall time)
+    static CPU: Mutex<Option<(u64, std::time::Instant)>> = Mutex::new(None);
+    let avg = {
+        let mut mean = MEAN.lock().unwrap_or_else(|e| e.into_inner());
+        mean.2 += fps * secs;
+        mean.3 += secs;
+        if draws >= 500.0 {
+            mean.0 += fps * secs;
+            mean.1 += secs;
+        }
+        if mean.1 > 0.0 { mean.0 / mean.1 } else if mean.3 > 0.0 { mean.2 / mean.3 } else { fps }
+    };
+    // SAFETY: the current process's pseudo handle and valid output structures.
+    let (ram_gb, cpu_total) = unsafe {
+        let process = GetCurrentProcess();
+        let mut counters: PROCESS_MEMORY_COUNTERS = std::mem::zeroed();
+        counters.cb = std::mem::size_of::<PROCESS_MEMORY_COUNTERS>() as u32;
+        let ram = if GetProcessMemoryInfo(process, &mut counters, counters.cb) != 0 {
+            counters.WorkingSetSize as f64 / f64::from(1u32 << 30)
+        } else {
+            0.0
+        };
+        let zero = FILETIME { dwLowDateTime: 0, dwHighDateTime: 0 };
+        let (mut created, mut exited, mut kernel, mut user) = (zero, zero, zero, zero);
+        let total = if GetProcessTimes(process, &mut created, &mut exited, &mut kernel, &mut user) != 0 {
+            let t = |f: FILETIME| (u64::from(f.dwHighDateTime) << 32) | u64::from(f.dwLowDateTime);
+            Some(t(kernel) + t(user))
+        } else {
+            None
+        };
+        (ram, total)
+    };
+    let cpu = match cpu_total {
+        Some(total) => {
+            let now = std::time::Instant::now();
+            let mut last = CPU.lock().unwrap_or_else(|e| e.into_inner());
+            let cores = std::thread::available_parallelism().map_or(1, |n| n.get()) as f64;
+            let percent = last.map_or(0.0, |(before, at)| {
+                let wall = now.duration_since(at).as_secs_f64();
+                if wall > 0.0 { (total.saturating_sub(before) as f64 / 1e7 / wall / cores * 100.0).clamp(0.0, 100.0) } else { 0.0 }
+            });
+            *last = Some((total, now));
+            percent
+        }
+        None => 0.0,
+    };
+    (avg, ram_gb, cpu)
+}
+
 /// Of the preparing: title memory copies (microseconds, bytes) and texture
 /// refreshes (microseconds, bytes hashed), since the last frame-rate line.
 pub(crate) static PREPARING: [std::sync::atomic::AtomicU64; 4] = [
@@ -10383,7 +10449,13 @@
             self.caption = Some(CAPTION.encode_utf16().collect());
         }
         let Some(caption) = &self.caption else { return };
-        let text = format!(" | VIctory {fps:.0} fps {ms:.1} ms/frame {draws:.0} draws/frame");
+        let (avg, ram_gb, cpu_percent) = caption_measures(fps, elapsed.as_secs_f64(), draws);
+        let (vram_used, vram_budget) = crate::host::host().and_then(|h| h.video_memory()).map_or((0, 0), |[budget, used, ..]| (used >> 20, budget >> 20));
+        let build = std::env::var("VICTORY_BUILD_TAG").unwrap_or_else(|_| "R27".to_owned());
+        let text = format!(
+            " | {fps:.1} fps | media {avg:.1} fps | {ms:.0} ms | {build} | VRAM {vram_used}/{vram_budget} MB | RAM {ram_gb:.1} GB | CPU {cpu_percent:.0}% | GPU {}%",
+            CARD_BUSY_PERCENT.load(Ordering::Relaxed)
+        );
         let mut text: Vec<u16> = caption.iter().copied().chain(text.encode_utf16()).collect();
         text.push(0);
         // Setting the text waits for the window's thread (a title thread,
@@ -10414,7 +10486,7 @@
 }
 
 /// The name the window's caption starts with.
-const CAPTION: &str = "Brazil";
+const CAPTION: &str = "Bolinha";
 
 static TITLE_DIR: std::sync::OnceLock<std::path::PathBuf> = std::sync::OnceLock::new();
 
diff -ruN -x target -x Cargo.lock -x '*.rej' -x .git a/crates/victory-hle/src/modules/gameinput.rs b/crates/victory-hle/src/modules/gameinput.rs
--- a/crates/victory-hle/src/modules/gameinput.rs	2026-11-27 11:20:57.870053500 -0300
+++ b/crates/victory-hle/src/modules/gameinput.rs	2026-11-27 20:18:21.727203700 -0300
@@ -190,8 +190,11 @@
         (on(0x08) || on(b'R'), B),
         (on(0x20) || on(b'X'), X),
         (on(b'F') || on(b'Y'), Y),
-        (on(0x21) || (tab && shift), LEFT_SHOULDER),
-        (on(0x22) || (tab && !shift) || on(b'Q'), RIGHT_SHOULDER),
+        // As GTA V on PC: Tab is the weapon wheel (LB, and the tab to the
+        // left in menus), Q cover (RB, the tab to the right); Page Up / Page
+        // Down stay as the other keys for them.
+        (on(0x21) || tab, LEFT_SHOULDER),
+        (on(0x22) || on(b'Q'), RIGHT_SHOULDER),
         (control, LEFT_STICK),
         (mouse.middle || on(b'C'), RIGHT_STICK),
         (on(b'V'), VIEW),
@@ -1305,6 +1308,9 @@
         empty_until: [Option<Instant>; PADS],
         mouse_captured: bool,
         toggle_was_down: bool,
+        /// The mouse was captured when the window lost focus: capture it again
+        /// as soon as focus is back (`VICTORY_MOUSE_AUTOLOCK`).
+        relock_on_focus: bool,
     }
 
     impl Source for Host {
@@ -1377,6 +1383,9 @@
 
         fn pc_mouse(&mut self, enabled: bool, keys: &[KeyState]) -> Option<PcMouse> {
             if !enabled || !focused() {
+                if self.mouse_captured && enabled {
+                    self.relock_on_focus = true;
+                }
                 self.mouse_captured = false;
                 self.toggle_was_down = false;
                 PC_MOUSE_CAPTURED.store(false, Ordering::Relaxed);
@@ -1389,6 +1398,25 @@
                 self.mouse_captured = false;
             } else if toggle && !self.toggle_was_down {
                 self.mouse_captured = !self.mouse_captured;
+            } else if !self.mouse_captured && mouse_autolock() {
+                // As GTA V on PC: a click in the window (or focus coming back
+                // after Alt+Tab, if it was captured) makes the mouse the
+                // camera again; Esc / P free it, F2 still toggles it.
+                // SAFETY: plain queries of the foreground window and cursor.
+                let inside = unsafe {
+                    let window = GetForegroundWindow();
+                    let mut info = WINDOWINFO { cbSize: size_of::<WINDOWINFO>() as u32, ..Default::default() };
+                    let mut at = POINT::default();
+                    !window.is_null() && GetWindowInfo(window, &mut info) != 0 && GetCursorPos(&mut at) != 0
+                        && at.x >= info.rcClient.left && at.x < info.rcClient.right
+                        && at.y >= info.rcClient.top && at.y < info.rcClient.bottom
+                };
+                // SAFETY: plain async key state queries.
+                let click = unsafe { GetAsyncKeyState(0x01) < 0 || GetAsyncKeyState(0x02) < 0 };
+                let relock = std::mem::take(&mut self.relock_on_focus);
+                if inside && (click || relock) {
+                    self.mouse_captured = true;
+                }
             }
             self.toggle_was_down = toggle;
             if was_captured != self.mouse_captured {
@@ -1404,7 +1432,28 @@
                 }
             }
             if !self.mouse_captured {
-                return Some(PcMouse::default());
+                // The buttons count whenever the cursor is in the window, captured
+                // or not: holding the right button aims (LT) as GTA V on PC does,
+                // also right after Esc freed the mouse. No camera movement.
+                // SAFETY: plain queries of the foreground window, cursor and keys.
+                return Some(unsafe {
+                    let window = GetForegroundWindow();
+                    let mut info = WINDOWINFO { cbSize: size_of::<WINDOWINFO>() as u32, ..Default::default() };
+                    let mut at = POINT::default();
+                    let inside = !window.is_null() && GetWindowInfo(window, &mut info) != 0 && GetCursorPos(&mut at) != 0
+                        && at.x >= info.rcClient.left && at.x < info.rcClient.right
+                        && at.y >= info.rcClient.top && at.y < info.rcClient.bottom;
+                    if inside {
+                        PcMouse {
+                            aim: GetAsyncKeyState(0x02) < 0,
+                            fire: GetAsyncKeyState(0x01) < 0,
+                            middle: GetAsyncKeyState(0x04) < 0,
+                            ..Default::default()
+                        }
+                    } else {
+                        PcMouse::default()
+                    }
+                });
             }
             let mut info = WINDOWINFO { cbSize: size_of::<WINDOWINFO>() as u32, ..Default::default() };
             let mut position = POINT::default();
@@ -1444,6 +1493,13 @@
         }
     }
 
+    /// Whether a click in the window captures the mouse as the camera, as GTA V
+    /// on PC keeps it (`VICTORY_MOUSE_AUTOLOCK`, on unless `0`).
+    fn mouse_autolock() -> bool {
+        static ON: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
+        *ON.get_or_init(|| std::env::var("VICTORY_MOUSE_AUTOLOCK").map_or(true, |value| value.trim() != "0"))
+    }
+
     fn mouse_sensitivity() -> f32 {
         static SENSITIVITY: std::sync::OnceLock<f32> = std::sync::OnceLock::new();
         *SENSITIVITY.get_or_init(|| {
diff -ruN -x target -x Cargo.lock -x '*.rej' -x .git a/crates/victory-hle/src/modules/lifecycle.rs b/crates/victory-hle/src/modules/lifecycle.rs
--- a/crates/victory-hle/src/modules/lifecycle.rs	2026-11-27 11:20:57.870053500 -0300
+++ b/crates/victory-hle/src/modules/lifecycle.rs	2026-11-27 20:16:26.702285000 -0300
@@ -154,7 +154,7 @@
 fn caption(parent: HWND, hwnd: HWND) {
     if parent.is_null() && !hwnd.is_null() {
         // SAFETY: a window this thread just created, and a NUL-terminated text.
-        unsafe { wm::SetWindowTextW(hwnd, w!("Brazil | VIctory")) };
+        unsafe { wm::SetWindowTextW(hwnd, w!("Bolinha")) };
     }
 }
 
diff -ruN -x target -x Cargo.lock -x '*.rej' -x .git a/crates/victory-loader/src/lib.rs b/crates/victory-loader/src/lib.rs
--- a/crates/victory-loader/src/lib.rs	2026-11-27 11:51:28.424359400 -0300
+++ b/crates/victory-loader/src/lib.rs	2026-11-27 19:10:51.334565500 -0300
@@ -66,7 +66,8 @@
 pub use thunks::{UnimplementedPolicy, unimplemented_call_count};
 #[cfg(windows)]
 pub use windows::{
-    BindReport, LoadedImage, MissingImport, WithTitleDlls, load, load_title_dll, load_title_dlls,
+    BindReport, LoadedImage, MissingImport, SlotError, WithTitleDlls, load, load_title_dll,
+    load_title_dlls,
 };
 
 /// `DLL_PROCESS_ATTACH`, for TLS callbacks.
diff -ruN -x target -x Cargo.lock -x '*.rej' -x .git a/crates/victory-loader/src/tls.rs b/crates/victory-loader/src/tls.rs
--- a/crates/victory-loader/src/tls.rs	2026-11-27 11:51:28.428358700 -0300
+++ b/crates/victory-loader/src/tls.rs	2026-11-27 19:10:51.334565500 -0300
@@ -18,7 +18,8 @@
 };
 use windows_sys::Win32::System::Threading::GetCurrentProcess;
 
-const SCN_MEM_EXECUTE: u32 = 0x2000_0000;
+/// A section flag: the section holds code.
+pub(crate) const SCN_MEM_EXECUTE: u32 = 0x2000_0000;
 const TLS64_ADDRESS_OF_INDEX: usize = 16;
 /// `mov r64, gs:[0x58]` is `65 REX 8B ModRM 25 58 00 00 00`.
 const LOAD_LEN: usize = 9;
diff -ruN -x target -x Cargo.lock -x '*.rej' -x .git a/crates/victory-loader/src/windows.rs b/crates/victory-loader/src/windows.rs
--- a/crates/victory-loader/src/windows.rs	2026-11-27 11:51:28.429359100 -0300
+++ b/crates/victory-loader/src/windows.rs	2026-11-27 19:10:51.335064400 -0300
@@ -14,6 +14,7 @@
 use windows_sys::Win32::System::Memory::{PAGE_READWRITE, VirtualProtect};
 
 use crate::thunks::{ImportSite, ThunkBlock, UnimplementedPolicy};
+use crate::tls::SCN_MEM_EXECUTE;
 use crate::{
     DLL_PROCESS_ATTACH, DLL_PROCESS_DETACH, ImportResolver, PreparedImage, Provenance, Resolution,
     prepare,
@@ -198,6 +199,48 @@
     }
 }
 
+/// Why an address in an image could not be used for a hook.
+#[derive(Debug, thiserror::Error)]
+pub enum SlotError {
+    #[error("{rva:#x} is outside the image")]
+    OutsideImage { rva: u32 },
+    #[error("the pointer slot at {rva:#x} is not 8-byte aligned")]
+    Misaligned { rva: u32 },
+    #[error("the pointer slot at {rva:#x} is not in a data section")]
+    NotData { rva: u32 },
+    #[error("{rva:#x} is not in a code section")]
+    NotCode { rva: u32 },
+    #[error("the page of the slot at {rva:#x} could not be made writable: {error}")]
+    Unwritable { rva: u32, error: std::io::Error },
+}
+
+// A pointer slot is read and written as one `usize`.
+const _: () = assert!(size_of::<usize>() == 8);
+
+/// Writes `value` into the slot at `slot`, whose offset in its image is
+/// `rva`, making its page writable for the write only.
+///
+/// # Safety
+///
+/// `slot` is an 8-byte aligned slot inside a mapped image that no other
+/// thread uses while it is written.
+unsafe fn write_slot(slot: *mut usize, rva: u32, value: usize) -> Result<(), SlotError> {
+    let mut old = 0;
+    // SAFETY: the slot is inside a mapped image, per the caller.
+    if unsafe { VirtualProtect(slot as *const c_void, 8, PAGE_READWRITE, &mut old) } == 0 {
+        return Err(SlotError::Unwritable {
+            rva,
+            error: std::io::Error::last_os_error(),
+        });
+    }
+    // SAFETY: inside the image, now writable, 8-byte aligned per the caller.
+    unsafe { slot.write_volatile(value) };
+    let mut ignored = 0;
+    // SAFETY: restoring the protection we just changed.
+    unsafe { VirtualProtect(slot as *const c_void, 8, old, &mut ignored) };
+    Ok(())
+}
+
 fn write_if_changed(path: &Path, bytes: &[u8]) -> Result<()> {
     crate::publish::write_if_changed(path, bytes)
         .with_context(|| format!("publishing {}", path.display()))
@@ -295,24 +338,83 @@
         Ok(report)
     }
 
+    /// Whether the `len` bytes at `rva` lie in one section whose code flag
+    /// is `code`; `None` when no section holds them.
+    fn in_code(&self, rva: u32, len: u32) -> Option<bool> {
+        let end = rva.checked_add(len)?;
+        self.info
+            .sections
+            .iter()
+            .find(|section| {
+                let section_end = section.rva.checked_add(section.virtual_size);
+                rva >= section.rva && section_end.is_some_and(|section_end| end <= section_end)
+            })
+            .map(|section| section.characteristics & SCN_MEM_EXECUTE != 0)
+    }
+
+    /// The 8-byte pointer slot at `rva`: aligned, and in a data section.
+    fn pointer_slot(&self, rva: u32) -> Result<*mut usize, SlotError> {
+        if !rva
+            .checked_add(8)
+            .is_some_and(|end| end <= self.info.size_of_image)
+        {
+            return Err(SlotError::OutsideImage { rva });
+        }
+        if !rva.is_multiple_of(8) {
+            return Err(SlotError::Misaligned { rva });
+        }
+        if self.in_code(rva, 8) != Some(false) {
+            return Err(SlotError::NotData { rva });
+        }
+        Ok((self.base() + rva as usize) as *mut usize)
+    }
+
+    /// The address of the code at `rva`, in a code section.
+    pub fn code_address(&self, rva: u32) -> Result<usize, SlotError> {
+        if rva >= self.info.size_of_image {
+            return Err(SlotError::OutsideImage { rva });
+        }
+        if self.in_code(rva, 1) != Some(true) {
+            return Err(SlotError::NotCode { rva });
+        }
+        Ok(self.base() + rva as usize)
+    }
+
+    /// The pointer in the slot at `rva`, read before a hook is placed there.
+    ///
+    /// # Safety
+    ///
+    /// No title thread runs yet, and the slot's page is readable.
+    pub unsafe fn read_pointer(&self, rva: u32) -> Result<usize, SlotError> {
+        let slot = self.pointer_slot(rva)?;
+        // SAFETY: eight aligned bytes inside the mapped image, checked by
+        // `pointer_slot`; readable and not written by the title, per the
+        // caller.
+        Ok(unsafe { slot.read_volatile() })
+    }
+
+    /// Puts `pointer` in the slot at `rva`, for a hook placed before the
+    /// title runs.
+    ///
+    /// # Safety
+    ///
+    /// No title thread runs yet: the slot's page is writable until the
+    /// write is done.
+    pub unsafe fn write_pointer(&self, rva: u32, pointer: usize) -> Result<(), SlotError> {
+        let slot = self.pointer_slot(rva)?;
+        // SAFETY: an aligned slot inside the image, checked by
+        // `pointer_slot`; the caller has no title thread running.
+        unsafe { write_slot(slot, rva, pointer) }
+    }
+
     /// Protects and restores each slot on its own: import tables can sit in
     /// sections with different protections (delay-load tables in `.didat`).
     fn write_slots(&self, slots: &[(u32, usize)]) -> Result<()> {
         for &(rva, address) in slots {
-            let slot = (self.base() + rva as usize) as *mut u64;
-            let mut old = 0;
-            // SAFETY: the parser only yields slots inside the image.
-            if unsafe { VirtualProtect(slot as *const c_void, 8, PAGE_READWRITE, &mut old) } == 0 {
-                bail!(
-                    "VirtualProtect(IAT slot {rva:#x}) failed: {}",
-                    std::io::Error::last_os_error()
-                );
-            }
-            // SAFETY: inside the image, now writable, 8-byte aligned by the PE format.
-            unsafe { slot.write_volatile(address as u64) };
-            let mut ignored = 0;
-            // SAFETY: restoring the protection we just changed.
-            unsafe { VirtualProtect(slot as *const c_void, 8, old, &mut ignored) };
+            let slot = (self.base() + rva as usize) as *mut usize;
+            // SAFETY: the parser only yields slots inside the image, 8-byte
+            // aligned by the PE format.
+            unsafe { write_slot(slot, rva, address) }?;
         }
         Ok(())
     }
diff -ruN -x target -x Cargo.lock -x '*.rej' -x .git a/crates/victory-loader/tests/load_probe.rs b/crates/victory-loader/tests/load_probe.rs
--- a/crates/victory-loader/tests/load_probe.rs	2026-11-27 11:51:28.429359100 -0300
+++ b/crates/victory-loader/tests/load_probe.rs	2026-11-27 19:10:51.335064400 -0300
@@ -7,7 +7,7 @@
 use std::process::Command;
 
 use victory_loader::{
-    ImportResolver, Provenance, Resolution, UnimplementedPolicy, WithTitleDlls, prepare,
+    ImportResolver, Provenance, Resolution, SlotError, UnimplementedPolicy, WithTitleDlls, prepare,
     unimplemented_call_count,
 };
 use victory_pe::ImportSymbol;
@@ -160,6 +160,56 @@
     assert_eq!(report.missing.len(), 1);
     assert_eq!(report.missing[0].symbol, "VIctoryProbeNotImplemented");
 
+    // A hook's pointer swap, on a bound import slot, and put back. No
+    // title thread runs: the probe's code is only called below.
+    let slot = image.info().imports[0].entries[0].iat_slot_rva;
+    let size = image.info().size_of_image;
+    // SAFETY: nothing runs the probe's code until the slot is put back.
+    unsafe {
+        let bound = image.read_pointer(slot).unwrap();
+        assert_ne!(bound, 0);
+        image.write_pointer(slot, 0x1234_5678).unwrap();
+        assert_eq!(image.read_pointer(slot).unwrap(), 0x1234_5678);
+        image.write_pointer(slot, bound).unwrap();
+        assert_eq!(image.read_pointer(slot).unwrap(), bound);
+        // Aligned, but at the end of the image or where offsets wrap.
+        for outside in [size, u32::MAX - 7] {
+            assert!(
+                matches!(
+                    image.read_pointer(outside),
+                    Err(SlotError::OutsideImage { .. })
+                ),
+                "{outside:#x}"
+            );
+        }
+        assert!(matches!(
+            image.write_pointer(size, 0),
+            Err(SlotError::OutsideImage { .. })
+        ));
+        assert!(matches!(
+            image.write_pointer(slot + 4, 0),
+            Err(SlotError::Misaligned { .. })
+        ));
+        // Code is no pointer slot, and a pointer slot is no code.
+        let entry = image.info().entry_rva;
+        assert!(matches!(
+            image.read_pointer(entry & !7),
+            Err(SlotError::NotData { .. })
+        ));
+        assert_eq!(
+            image.code_address(entry).unwrap(),
+            image.base() + entry as usize
+        );
+        assert!(matches!(
+            image.code_address(slot),
+            Err(SlotError::NotCode { .. })
+        ));
+        assert!(matches!(
+            image.code_address(size),
+            Err(SlotError::OutsideImage { .. })
+        ));
+    }
+
     let call = |name: &str| -> usize { image.export(name).unwrap_or_else(|| panic!("{name}")) };
     // SAFETY: the exports have the signatures declared in the fixture and
     // every import they use has been bound.
diff -ruN -x target a/apps/victory/src/run.rs b/apps/victory/src/run.rs
--- a/apps/victory/src/run.rs	2026-11-27 11:20:57.869054400 -0300
+++ b/apps/victory/src/run.rs	2026-11-27 19:11:16.333802400 -0300
@@ -171,6 +171,27 @@
         // SAFETY: the image stays mapped, and nothing of it has run yet.
         unsafe { victory_loader::write_sites::apply_asked(&image_name, image.base(), size) };
     }
+    // Keyboard key caps over the title's button pictures (VICTORY_PROMPTS=keys,
+    // after Marvisak/VIctory#3433), for the one build whose offsets are known.
+    #[cfg(windows)]
+    if execute && std::env::var("VICTORY_PROMPTS").is_ok_and(|v| v.trim().eq_ignore_ascii_case("keys")) {
+        const SERIES_1_0_2_1: &str = "b99f876b74d4a77f03af5f878223b27bd647b5c35a79d5decd9f716504239e93";
+        if hash.eq_ignore_ascii_case(SERIES_1_0_2_1) {
+            use victory_game::prompts::{CodeOffset, HookOffsets, PointerOffset};
+            let offsets = HookOffsets {
+                movie_address_builder: PointerOffset(0x62f_3388),
+                string_assign: CodeOffset(0xeb_ba60),
+            };
+            // SAFETY: the image of the build the offsets belong to is mapped and
+            // bound, and no title thread runs yet.
+            match unsafe { victory_game::prompts::hook::install(&image, offsets) } {
+                Ok(()) => println!("prompts        keyboard keys: hook placed"),
+                Err(refused) => println!("prompts        gamepad pictures: {refused}"),
+            }
+        } else {
+            println!("prompts        gamepad pictures: the keys need build 1.0.2.1");
+        }
+    }
     if !execute {
         println!("not executing (pass --execute to start the title)");
         return Ok(());
```
