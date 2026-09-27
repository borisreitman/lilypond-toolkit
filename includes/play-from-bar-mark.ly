% Insert \playBarMark in a section macro to mark its start in the PDF.
% If the macro is used more than once, each use gets its own marker;
% the bar number comes from LilyPond's counter at that spot.

#(define (play-bar-mark-formatter mark context)
   (markup #:normal-text #:fontsize -2
     (string-append "▶ "
       (number->string (ly:context-property context 'currentBarNumber)))))

playBarMark = {
  \set Score.rehearsalMarkFormatter = #play-bar-mark-formatter
  \mark \default
  \skip 1*0
}
