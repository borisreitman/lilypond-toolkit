\version "2.26.0"

\include "play-from-bar-mark.ly"

\header {
  title = "Hello, LilyPond"
  composer = "Test"
}

\score {
  \new PianoStaff <<
    \new Staff = "RH" {
      \clef treble
      \key c \major
      \time 4/4
      \relative c' {
        \playBarMark
        c4 e g c | e d c b |
        c2. e4 | g2 c2 |
      }
    }
    \new Staff = "LH" {
      \clef bass
      \relative c, {
        c8 e g e c e g e | g,8 b d b g b d b |
        c8 e g e c e g e | c2 g,2 |
      }
    }
  >>
  \layout { }
  \midi {
    \tempo 4 = 108
  }
}
