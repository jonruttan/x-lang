; sys/web.x -- Web: a window in a browser tab, answering Sdl's messages, so
; a program written to Sdl shows its picture and plays its sound in a browser
; when SDL3 is not there.
;
; open listens on a TCP port and serves one page.  The page's canvas shows
; the picture and Web Audio plays the sound; a WebSocket carries frames and
; samples to it, and keys and gamepad input back as Sdl's events.  Nothing
; runs but x and the browser: the socket is Socket's, the handshake's digest
; Sha1's, and the page is the string below.
;
;   (Web listen! host ports)    -> host; where the next open listens
;   (Web available?)            -> #t: nothing outside x is needed
;   (Web open title w h scale)  -> a window: a w x h RGBA picture
;   (Web url win)               -> the page's address
;   (Web scaling! win mode)     -> win; whole or fit, as Sdl's
;   (Web canvas win)            -> a zeroed RGBA buffer the window's size
;   (Web draw! win buf)         -> the buffer kept as the frame, not yet sent
;   (Web present! win)          -> the frame sent to the page
;   (Web show! win buf)         -> draw! then present!
;   (Web read-pixels win)       -> the frame drawn last
;   (Web poll)                  -> the next event, or nil
;   (Web post-key! code)        -> queues a key-down event, as a key press
;   (Web fullscreen! win on)    -> asks the page for fullscreen, or back
;   (Web key name) (Web keys) (Web buttons) (Web axes) -> as Sdl's
;   (Web close win)             -> the page told, the sockets closed
;   (Web audio-open rate chans) -> a stream of signed 16-bit frames
;   (Web audio-put! s buf n)    -> n bytes of buf sent to play after the rest
;   (Web audio-queued s)        -> bytes sent and not yet played
;   (Web audio-clear! s)        -> the page told to drop what it has
;   (Web audio-close s)         -> the stream released
;
; One window at a time, as SDL has one event queue: poll and the audio
; methods take no window and act on the one open.  Every call that touches
; the window first serves the sockets without waiting: a new connection gets
; the page, or becomes the page's WebSocket, which replaces any before it and
; is sent the size, the title, the open streams and the last frame.  A page
; that goes away is waited for again; it is not a close event.
;
; A browser enters fullscreen only within a few seconds of a key or a click,
; so fullscreen! asked for after a key works, and one asked for later waits
; for the next key or click on the page.  Sound starts at the first key or
; click, for the same reason.  audio-queued is reckoned from the clock: what
; was sent plays at the stream's rate from when it was sent.
;
; Messages to the page are text, a word and its arguments, or binary, a tag
; byte then data: F and the RGBA bytes, A and a stream number then samples.
; Messages from the page are an event's words: "key-down 97 1 0".

(module x/sys/web)
(import x/type/class)
(import x/core/list)
(import x/sys/socket)
(import x/sys/posix)
(import x/sys/file)
(import x/sys/sdl)
(import x/codec/sha1)
(import x/codec/base64)
(import x/core/doors char->int int/ ptr-set! str->ptr str-byte-ref str-make)

(def-class Web ()
  (doc "A window in a browser tab: Sdl's messages answered by a page that shows an RGBA picture on a canvas, plays signed 16-bit sound through Web Audio, and sends keys and gamepad input back over a WebSocket."
    (note "open listens on 127.0.0.1, ports 8080 to 8089 then any the kernel gives, unless listen! names others, and prints the page's address on stderr.")
    (example "(Web key (lit up))" "1073741906")
    (see open) (see show!) (see poll) (see listen!))
  (static
    (%window-cell (pair () ()))
    (%listen-cell (pair (list "127.0.0.1" (list 8080 8081 8082 8083 8084 8085 8086 8087 8088 8089 0)) ()))
    (%stream-count (pair 0 ()))
    (%guid "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
    (%page "<!doctype html><html><head><meta charset=utf-8><title>x</title><style>html,body{margin:0;height:100%;background:#000;overflow:hidden}canvas{position:absolute;image-rendering:pixelated}</style></head><body><canvas id=c></canvas><script>
var c=document.getElementById('c'),g=c.getContext('2d'),W=0,H=0,mode='whole',img=null,ws=null,ac=null,want=false,streams={},pads={};
var named={ArrowUp:1073741906,ArrowDown:1073741905,ArrowLeft:1073741904,ArrowRight:1073741903,Escape:27,Enter:13,NumpadEnter:13,Backspace:8,Tab:9,Space:32,Delete:127,Insert:1073741897,Home:1073741898,PageUp:1073741899,End:1073741901,PageDown:1073741902};
var punct={Minus:'-',Equal:'=',BracketLeft:'[',BracketRight:']',Backslash:String.fromCharCode(92),Semicolon:';',Quote:String.fromCharCode(39),Comma:',',Period:'.',Slash:'/',Backquote:'`'};
var BN=['south','east','west','north','left-shoulder','right-shoulder','','','back','start','left-stick','right-stick','dpad-up','dpad-down','dpad-left','dpad-right','guide'];
var AN=['left-x','left-y','right-x','right-y'];
function fit(){if(!W)return;var vw=innerWidth,vh=innerHeight,s=Math.min(vw/W,vh/H);if(mode=='whole')s=Math.max(1,Math.floor(s));var cw=Math.round(W*s),ch=Math.round(H*s);c.style.width=cw+'px';c.style.height=ch+'px';c.style.left=((vw-cw)>>1)+'px';c.style.top=((vh-ch)>>1)+'px';}
addEventListener('resize',fit);
function send(t){if(ws&&ws.readyState==1)ws.send(t);}
function full(on){var d=document;if(on){want=!d.fullscreenElement;if(want&&d.documentElement.requestFullscreen)d.documentElement.requestFullscreen().then(function(){want=false;},function(){});}else{want=false;if(d.fullscreenElement)d.exitFullscreen();}}
function stop(id){var s=streams[id];if(!s)return;s.nodes.forEach(function(n){try{n.stop();}catch(e){}});s.nodes=[];s.next=0;}
function control(a){var k=a[0];
if(k=='title')document.title=a.slice(1).join(' ');
else if(k=='size'){W=+a[1];H=+a[2];c.width=W;c.height=H;img=g.createImageData(W,H);fit();}
else if(k=='scaling'){mode=a[1];fit();}
else if(k=='fullscreen')full(a[1]=='1');
else if(k=='audio-open')streams[a[1]]={rate:+a[2],chans:+a[3],next:0,nodes:[]};
else if(k=='audio-clear')stop(a[1]);
else if(k=='audio-close'){stop(a[1]);delete streams[a[1]];}}
function play(id,buf){var s=streams[id];if(!s||!ac||ac.state!='running')return;var pcm=new Int16Array(buf,2,(buf.byteLength-2)>>1),n=Math.floor(pcm.length/s.chans);if(n<1)return;
var ab=ac.createBuffer(s.chans,n,s.rate);for(var ch=0;ch<s.chans;ch++){var d=ab.getChannelData(ch);for(var i=0;i<n;i++)d[i]=pcm[i*s.chans+ch]/32768;}
var src=ac.createBufferSource();src.buffer=ab;src.connect(ac.destination);var t=Math.max(s.next,ac.currentTime+0.05);src.start(t);s.next=t+ab.duration;s.nodes.push(src);
src.onended=function(){var i=s.nodes.indexOf(src);if(i>=0)s.nodes.splice(i,1);};}
function data(buf){var b=new Uint8Array(buf);if(b[0]==70){if(img&&b.length>=1+W*H*4){img.data.set(b.subarray(1,1+W*H*4));g.putImageData(img,0,0);}}else if(b[0]==65)play(b[1],buf);}
function connect(){ws=new WebSocket('ws://'+location.host+'/socket');ws.binaryType='arraybuffer';
ws.onmessage=function(e){if(typeof e.data=='string')control(e.data.split(' '));else data(e.data);};
ws.onclose=function(){ws=null;setTimeout(connect,1000);};}
function wake(){if(!ac){var A=window.AudioContext||window.webkitAudioContext;if(A)ac=new A();}if(ac&&ac.state=='suspended')ac.resume();if(want)full(true);}
function code(e){var k=e.code;if(named[k])return named[k];
if(/^F[0-9]+$/.test(k)){var f=+k.slice(1);if(f>=1&&f<=12)return 1073741881+f;}
if(/^Key[A-Z]$/.test(k))return k.charCodeAt(3)+32;if(/^Digit[0-9]$/.test(k))return k.charCodeAt(5);if(/^Numpad[0-9]$/.test(k))return k.charCodeAt(6);
if(punct[k])return punct[k].charCodeAt(0);if(e.key&&e.key.length==1)return e.key.toLowerCase().charCodeAt(0);return 0;}
function mods(e){return (e.shiftKey?1:0)|(e.ctrlKey?64:0)|(e.altKey?256:0)|(e.metaKey?1024:0);}
function key(down){return function(e){wake();var k=code(e);if(!k)return;e.preventDefault();send((down?'key-down ':'key-up ')+k+' '+mods(e)+' '+(e.repeat?1:0));};}
addEventListener('keydown',key(true));addEventListener('keyup',key(false));addEventListener('mousedown',wake);
function axis(v){return Math.max(-32768,Math.min(32767,Math.round(v*32767)));}
function padLoop(){var gp=navigator.getGamepads?navigator.getGamepads():[];var seen={};
for(var i=0;i<gp.length;i++){var p=gp[i];if(!p)continue;seen[p.index]=1;var st=pads[p.index];if(!st){st=pads[p.index]={b:[],a:[]};send('pad-added '+p.index);}
for(var j=0;j<p.buttons.length&&j<BN.length;j++){if(j==6||j==7){var v=axis(p.buttons[j].value);if((v>>10)!=(st.a[j]>>10)){st.a[j]=v;send('pad-axis '+(j==6?'left-trigger':'right-trigger')+' '+v+' '+p.index);}continue;}
var on=p.buttons[j].pressed;if(on!=!!st.b[j]){st.b[j]=on;wake();send((on?'pad-down ':'pad-up ')+BN[j]+' '+p.index);}}
for(var k=0;k<p.axes.length&&k<AN.length;k++){var v=axis(p.axes[k]);if((v>>10)!=(st.a[16+k]>>10)){st.a[16+k]=v;send('pad-axis '+AN[k]+' '+v+' '+p.index);}}}
for(var q in pads)if(!seen[q]){delete pads[q];send('pad-removed '+q);}
requestAnimationFrame(padLoop);}
connect();requestAnimationFrame(padLoop);
</script></body></html>
")

    (method listen! (self (param host STRING "Dotted-quad address to listen on: 127.0.0.1 for this machine only, 0.0.0.0 for every interface, as in a container")
                          (param ports INTEGER|LIST "The port, or the candidates to try in order, as Socket tcp-listen-on takes them"))
      (doc "Name where the next open listens."
        (returns STRING "The host")
        (example "(Web listen! \"127.0.0.1\" 8080)" "\"127.0.0.1\""))
      (%set-first! (Web %listen-cell) (list host ports))
      host)

    (method available? (self)
      (doc "Whether a Web window can be opened: always, as it needs nothing outside x."
        (returns BOOL "#t")
        (example "(Web available?)" "#t"))
      #t)

    (method keys (self)
      (doc "Keycodes by name for keys that are not printable characters: Sdl's, as the page sends SDL's keycodes."
        (returns LIST "((name . keycode) ...)")
        (example "(first (Web keys))" "('up . 1073741906)"))
      (Sdl keys))

    (method key (self (param name SYMBOL "A key name from (Web keys)"))
      (doc "The keycode the page sends for a named key."
        (returns INTEGER "SDL's keycode")
        (example "(Web key (lit escape))" "27"))
      (Sdl key name))

    (method buttons (self)
      (doc "Gamepad button names, as Sdl's: the page maps a standard gamepad's buttons to them."
        (returns LIST "Button names")
        (example "(first (Web buttons))" "'south"))
      (Sdl buttons))

    (method axes (self)
      (doc "Gamepad axis names, as Sdl's."
        (returns LIST "Axis names")
        (example "(first (Web axes))" "'left-x"))
      (Sdl axes))

    (method error (self)
      (doc "The last error message: always empty, as Web raises its errors."
        (returns STRING "\"\"")
        (example "(Web error)" "\"\""))
      "")

    ; --- The window: a vector of the listening socket, the page's socket or
    ; nil, the picture's width and height, the title, the bytes read from the
    ; page and not yet whole messages, the events waiting for poll, the frame
    ; drawn last, the scaling, whether fullscreen, and the open streams.
    (method %ref (self (param win VECTOR "A window from open") (param field SYMBOL "A field name"))
      (doc "A field of the window."
        (returns ANY "Its value")
        (sample "(Web %ref win (lit page))" "the page's socket, or nil"))
      (Vector ref (Web %field field) win))

    (method %set! (self (param win VECTOR "A window from open") (param field SYMBOL "A field name") (param v ANY "The new value"))
      (doc "Set a field of the window."
        (returns ANY "v")
        (sample "(Web %set! win (lit page) ())" "nil"))
      (Vector set! (Web %field field) v win)
      v)

    (method %field (self (param field SYMBOL "A field name"))
      (doc "The slot that holds a field of the window."
        (returns INTEGER "The slot")
        (example "(Web %field (lit page))" "1"))
      (match
        ((eq? field (lit listener)) 0) ((eq? field (lit page)) 1)
        ((eq? field (lit w)) 2) ((eq? field (lit h)) 3) ((eq? field (lit title)) 4)
        ((eq? field (lit unread)) 5) ((eq? field (lit events)) 6) ((eq? field (lit frame)) 7)
        ((eq? field (lit scaling)) 8) ((eq? field (lit fullscreen)) 9) ((eq? field (lit streams)) 10)
        (#t (Err raise (lit value) "Web: no such field" field))))

    (method %window (self)
      (doc "The window open, or nil."
        (returns ANY "The window")
        (sample "(Web %window)" "the window, or nil"))
      (first (Web %window-cell)))

    (method open (self (param title STRING "The page's title")
                       (param w INTEGER "Picture width in pixels")
                       (param h INTEGER "Picture height in pixels")
                       (param scale INTEGER "Taken for Sdl's sake: the page fits the picture to the tab"))
      (doc "Listen for a browser and keep a w x h RGBA picture for it, scaled by whole multiples with nearest-pixel sampling. Prints the page's address on stderr; frames drawn before a page connects are kept, and the last is sent when one does."
        (returns VECTOR "The window")
        (sample "(Web open \"x\" 320 200 3)" "a window, its page at http://127.0.0.1:8080/"))
      (unless (null? (Web %window))
        (Err raise (lit state) "Web open: a window is open already" ()))
      (def where (first (Web %listen-cell)))
      (def lfd (Socket tcp-listen-on (first where) (List ref 1 where)))
      (def win (Vector make 11 ()))
      (Vector set! 0 lfd win)
      (Web %set! win (lit w) w)
      (Web %set! win (lit h) h)
      (Web %set! win (lit title) title)
      (Web %set! win (lit scaling) (lit whole))
      (Web %set! win (lit fullscreen) #f)
      (%set-first! (Web %window-cell) win)
      (def line (Str8 append "Web: " title " is at " (Web url win) "\n"))
      (File write 2 line (Str8 length line))
      win)

    (method url (self (param win VECTOR "A window from open"))
      (doc "The address of the window's page."
        (returns STRING "An http URL")
        (sample "(Web url win)" "\"http://127.0.0.1:8080/\""))
      (def host (first (first (Web %listen-cell))))
      (Str8 append "http://" (if (equal? host "0.0.0.0") "127.0.0.1" host) ":"
                   (Str8 str (Socket local-port (Web %ref win (lit listener)))) "/"))

    ; --- Serving: each call that touches the window serves first.
    (method %serve! (self (param win VECTOR "A window from open"))
      (doc "Take any new connection and read whatever the page has sent, without waiting."
        (returns ANY "nil")
        (sample "(Web %serve! win)" "nil"))
      (def lfd (Web %ref win (lit listener)))
      (def page (Web %ref win (lit page)))
      (def ready (Sys poll (if (null? page)
                             (list (pair lfd (list (lit in))))
                             (list (pair lfd (list (lit in))) (pair page (list (lit in)))))
                           0))
      (List for-each (fn (_ r)
                       (if (= (first r) lfd)
                         (Web %connect! win (Socket accept lfd))
                         (Web %read! win)))
                     ready)
      ())

    (method %connect! (self (param win VECTOR "A window from open") (param fd INTEGER "A connection just accepted"))
      (doc "Answer one HTTP request on fd: the page, the WebSocket the page opens, or not found."
        (returns ANY "nil")
        (sample "(Web %connect! win fd)" "nil"))
      (def request (guard (_ "") (Web %request fd)))
      (def lower (Str8 downcase request))
      (match
        ((not (null? (Str8 index-of "upgrade: websocket" lower)))
          (Web %upgrade! win fd request lower))
        ((Str8 starts? "GET / " request)
          (do (guard (_ ()) (Web %respond fd "200 OK" "text/html; charset=utf-8" (Web %page)))
              (Socket close fd)))
        (#t
          (do (guard (_ ()) (Web %respond fd "404 Not Found" "text/plain" "not found\n"))
              (Socket close fd))))
      ())

    (method %request (self (param fd INTEGER "A connection"))
      (doc "An HTTP request's head, read until its blank line or 16 KB."
        (returns STRING "The request head")
        (sample "(Web %request fd)" "\"GET / HTTP/1.1\\r\\n...\""))
      (let more ((got ""))
        (if (or (not (null? (Str8 index-of "\r\n\r\n" got))) (> (Str8 length got) 16384))
          got
          (let ((s (Socket recv fd 4096)))
            (if (null? s) got (more (Str8 append got s)))))))

    (method %respond (self (param fd INTEGER "A connection") (param status STRING "Status line's code and words")
                           (param type STRING "Content-Type") (param body STRING "The body, text"))
      (doc "Send one HTTP response and its body."
        (returns ANY "nil")
        (sample "(Web %respond fd \"200 OK\" \"text/plain\" \"hi\")" "nil"))
      (Socket send fd (Str8 append "HTTP/1.1 " status "\r\nContent-Type: " type
                                   "\r\nContent-Length: " (Str8 str (Str8 length body))
                                   "\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" body))
      ())

    (method %header (self (param name STRING "A header name, lower case, with its colon")
                          (param request STRING "The request head")
                          (param lower STRING "The request head, lower case"))
      (doc "A request header's value, or nil."
        (returns ANY "The value, trimmed")
        (sample "(Web %header \"host:\" request lower)" "\"127.0.0.1:8080\""))
      (def at (Str8 index-of name lower))
      (if (null? at) ()
        (let ((from (+ at (Str8 length name))))
          (let ((tail (Str8 sub from (- (Str8 length request) from) request)))
            (let ((end (Str8 index-of "\r\n" tail)))
              (Str8 trim (if (null? end) tail (Str8 sub 0 end tail))))))))

    (method accept-key (self (param key STRING "A Sec-WebSocket-Key header's value"))
      (doc "The Sec-WebSocket-Accept answer to a WebSocket key (RFC 6455): the base64 of the SHA-1 of the key and the protocol's GUID."
        (returns STRING "The answer")
        (example "(Web accept-key \"dGhlIHNhbXBsZSBub25jZQ==\")" "\"s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\""))
      (def hex (Sha1 hex (Str8 append key (Web %guid))))
      (Base64 encode-bytes
        (let go ((i 38) (acc ()))
          (if (< i 0) acc
            (go (- i 2) (pair (%str->number (Str8 sub i 2 hex) 16) acc))))))

    (method %upgrade! (self (param win VECTOR "A window from open") (param fd INTEGER "A connection")
                            (param request STRING "Its request head") (param lower STRING "The head, lower case"))
      (doc "Make fd the page's WebSocket, in place of any before it, and send it the window's state."
        (returns ANY "nil")
        (sample "(Web %upgrade! win fd request lower)" "nil"))
      (def key (Web %header "sec-websocket-key:" request lower))
      (if (null? key)
        (do (guard (_ ()) (Web %respond fd "400 Bad Request" "text/plain" "no key\n"))
            (Socket close fd))
        (do (Web %drop! win)
            (Socket send fd (Str8 append "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
                                         "Connection: Upgrade\r\nSec-WebSocket-Accept: " (Web accept-key key)
                                         "\r\n\r\n"))
            (Web %set! win (lit page) fd)
            (Web %set! win (lit unread) ())
            (Web %tell! win (Str8 append "size " (Str8 str (Web %ref win (lit w))) " "
                                         (Str8 str (Web %ref win (lit h)))))
            (Web %tell! win (Str8 append "title " (Web %ref win (lit title))))
            (Web %tell! win (Str8 append "scaling " (Str8 str (Web %ref win (lit scaling)))))
            (when (Web %ref win (lit fullscreen)) (Web %tell! win "fullscreen 1"))
            (List for-each (fn (_ s) (Web %tell! win (Web %opened s))) (Web %ref win (lit streams)))
            (Web present! win)))
      ())

    (method %drop! (self (param win VECTOR "A window from open"))
      (doc "Forget the page's socket, closing it."
        (returns ANY "nil")
        (sample "(Web %drop! win)" "nil"))
      (def page (Web %ref win (lit page)))
      (unless (null? page)
        (do (Socket close page)
            (Web %set! win (lit page) ())
            (Web %set! win (lit unread) ())))
      ())

    ; --- WebSocket frames (RFC 6455).  Frames to the page are whole and
    ; unmasked; frames from it are masked.
    (method %send! (self (param win VECTOR "A window from open") (param op INTEGER "The opcode: 1 text, 2 binary, 8 close")
                         (param head STRING "The payload's first bytes") (param head-n INTEGER "How many")
                         (param body ANY "The rest of the payload, or nil") (param body-n INTEGER "How many bytes of body"))
      (doc "Send one frame to the page, if there is one; a page that has gone is dropped."
        (returns ANY "nil")
        (sample "(Web %send! win 1 \"hi\" 2 () 0)" "nil"))
      (def page (Web %ref win (lit page)))
      (unless (null? page)
        (let ((n (+ head-n body-n)))
          (let ((len-n (match ((< n 126) 0) ((< n 65536) 2) (#t 8))))
            (let ((frame (str-make (+ 2 len-n head-n 8))))
              (def p (str->ptr frame))
              (ptr-set! p 0 (+ 128 op) 1)
              (match
                ((= len-n 0) (ptr-set! p 1 n 1))
                ((= len-n 2) (do (ptr-set! p 1 126 1) (Web %put-be! p 2 n 2)))
                (#t (do (ptr-set! p 1 127 1) (Web %put-be! p 2 n 8))))
              (let copy ((i 0))
                (when (< i head-n)
                  (do (ptr-set! p (+ 2 len-n i) (& (char->int (str-byte-ref head i)) 255) 1) (copy (+ i 1)))))
              (guard (_ (Web %drop! win))
                (Socket send-run page frame (+ 2 len-n head-n))
                (when (> body-n 0) (Socket send-run page body body-n)))))))
      ())

    (method %put-be! (self (param p POINTER "Where") (param at INTEGER "Offset") (param v INTEGER "Value") (param n INTEGER "Bytes"))
      (doc "Write v as n big-endian bytes."
        (returns ANY "nil")
        (sample "(Web %put-be! p 2 300 2)" "nil"))
      (let go ((i (- n 1)) (v v))
        (when (>= i 0)
          (do (ptr-set! p (+ at i) (& v 255) 1) (go (- i 1) (int/ v 256)))))
      ())

    (method %tell! (self (param win VECTOR "A window from open") (param text STRING "A message: a word and its arguments"))
      (doc "Send the page a text message."
        (returns ANY "nil")
        (sample "(Web %tell! win \"scaling fit\")" "nil"))
      (Web %send! win 1 text (Str8 length text) () 0))

    (method %read! (self (param win VECTOR "A window from open"))
      (doc "Read what the page has sent and queue its events; a page that has closed is dropped."
        (returns ANY "nil")
        (sample "(Web %read! win)" "nil"))
      (def got (guard (_ ()) (Socket recv-bytes (Web %ref win (lit page)) 4096)))
      (if (null? got)
        (Web %drop! win)
        (Web %frames! win (List append (Web %ref win (lit unread)) got)))
      ())

    (method %frames! (self (param win VECTOR "A window from open") (param bytes LIST "Bytes read and not yet whole frames"))
      (doc "Take each whole frame from bytes, queue the events of its text, and keep the rest."
        (returns ANY "nil")
        (sample "(Web %frames! win bytes)" "nil"))
      (def n (List length bytes))
      (if (< n 2)
        (Web %set! win (lit unread) bytes)
        (let ((op (& (first bytes) 15))
              (len7 (& (first (rest bytes)) 127))
              (masked (> (& (first (rest bytes)) 128) 0)))
          (let ((len-n (match ((= len7 126) 2) ((= len7 127) 8) (#t 0))))
            (let ((head (+ 2 len-n (if masked 4 0))))
              (if (< n head)
                (Web %set! win (lit unread) bytes)
                (let ((len (if (= len-n 0) len7 (Web %get-be (List drop 2 bytes) len-n))))
                  (if (< n (+ head len))
                    (Web %set! win (lit unread) bytes)
                    (let ((payload (Web %unmask (List take len (List drop head bytes))
                                                (if masked (List take 4 (List drop (+ 2 len-n) bytes)) ()))))
                      (match
                        ((= op 1) (Web %queue! win (Web %event payload)))
                        ((= op 8) (Web %drop! win))
                        (#t ()))
                      (unless (null? (Web %ref win (lit page)))
                        (Web %frames! win (List drop (+ head len) bytes)))))))))))
      ())

    (method %get-be (self (param bytes LIST "Bytes") (param n INTEGER "How many"))
      (doc "The first n bytes read as a big-endian number."
        (returns INTEGER "The number")
        (example "(Web %get-be (list 1 44) 2)" "300"))
      (let go ((l bytes) (i 0) (v 0))
        (if (= i n) v (go (rest l) (+ i 1) (+ (* v 256) (first l))))))

    (method %unmask (self (param bytes LIST "A payload") (param mask LIST "Four mask bytes, or nil"))
      (doc "The payload with the mask taken off: each byte exclusive-or the mask's byte at its place, four round."
        (returns LIST "The bytes")
        (example "(Web %unmask (list 3 1) (list 1 2 3 4))" "(2 3)"))
      (if (null? mask) bytes
        (let go ((l bytes) (i 0) (acc ()))
          (if (null? l) (List reverse acc)
            (let ((a (first l)) (b (List ref (& i 3) mask)))
              (go (rest l) (+ i 1) (pair (- (| a b) (& a b)) acc)))))))

    (method %event (self (param bytes LIST "A text message's bytes: an event's words"))
      (doc "The event a message names: its first word a symbol, each other word a number when it reads as one and a symbol when not."
        (returns LIST "The event")
        (example "(Web %event (list 112 97 100 45 117 112 32 115 111 117 116 104 32 48))" "('pad-up 'south 0)"))
      (def word (fn (_ chars)
                  (def s (Web %text (List reverse chars)))
                  (def v (%str->number s))
                  (if (null? v) (Str8 ->sym s) v)))
      (let go ((l bytes) (chars ()) (acc ()))
        (match
          ((null? l) (List reverse (if (null? chars) acc (pair (word chars) acc))))
          ((= (first l) 32) (go (rest l) () (if (null? chars) acc (pair (word chars) acc))))
          (#t (go (rest l) (pair (first l) chars) acc)))))

    (method %text (self (param bytes LIST "Byte values"))
      (doc "A string of the bytes."
        (returns STRING "The string")
        (example "(Web %text (list 104 105))" "\"hi\""))
      (def n (List length bytes))
      (def s (str-make (+ n 1)))
      (def p (str->ptr s))
      (let go ((l bytes) (i 0))
        (unless (null? l)
          (do (ptr-set! p i (first l) 1) (go (rest l) (+ i 1)))))
      (ptr-set! p n 0 1)
      s)

    (method %queue! (self (param win VECTOR "A window from open") (param event LIST "An event"))
      (doc "Put an event at the end of the queue poll answers from."
        (returns ANY "nil")
        (sample "(Web %queue! win (list (lit quit)))" "nil"))
      (Web %set! win (lit events) (List append (Web %ref win (lit events)) (list event)))
      ())

    ; --- The picture.
    (method scaling! (self (param win VECTOR "A window from open")
                           (param mode SYMBOL "whole: whole multiples only; fit: as large as the tab allows, its shape kept"))
      (doc "Set how the page scales the picture to the tab: by whole multiples, or as large as fits."
        (returns VECTOR "The window")
        (sample "(Web scaling! win (lit fit))" "win"))
      (unless (or (eq? mode (lit whole)) (eq? mode (lit fit)))
        (Err raise (lit value) "Web scaling!: the mode is whole or fit" mode))
      (Web %set! win (lit scaling) mode)
      (Web %serve! win)
      (Web %tell! win (Str8 append "scaling " (Str8 str mode)))
      win)

    (method canvas (self (param win VECTOR "A window from open"))
      (doc "A zeroed RGBA buffer the size of the window's picture: transparent black."
        (returns STRING "A region of w*h*4 bytes")
        (sample "(Web canvas win)" "a 256000-byte region for 320 x 200"))
      (Sdl %zeroed (* 4 (Web %ref win (lit w)) (Web %ref win (lit h)))))

    (method draw! (self (param win VECTOR "A window from open")
                        (param buf STRING "An RGBA buffer the window's size"))
      (doc "Keep the buffer as the frame; nothing is sent until present!."
        (returns VECTOR "The window")
        (sample "(Web draw! win (Web canvas win))" "win"))
      (Web %set! win (lit frame) buf)
      win)

    (method present! (self (param win VECTOR "A window from open"))
      (doc "Send the frame drawn last to the page."
        (returns VECTOR "The window")
        (sample "(Web present! win)" "win"))
      (Web %serve! win)
      (def frame (Web %ref win (lit frame)))
      (unless (null? frame)
        (Web %send! win 2 "F" 1 frame (* 4 (Web %ref win (lit w)) (Web %ref win (lit h)))))
      win)

    (method show! (self (param win VECTOR "A window from open")
                        (param buf STRING "An RGBA buffer the window's size"))
      (doc "Draw the buffer and send it."
        (returns VECTOR "The window")
        (sample "(Web show! win buf)" "win"))
      (Web draw! win buf)
      (Web present! win))

    (method read-pixels (self (param win VECTOR "A window from open"))
      (doc "The frame drawn last, as an RGBA buffer; nil before any."
        (returns ANY "A region of w*h*4 bytes, or nil")
        (sample "(Web read-pixels win)" "the drawn frame"))
      (Web %ref win (lit frame)))

    (method fullscreen! (self (param win VECTOR "A window from open") (param on BOOL "#t for fullscreen, #f for a window"))
      (doc "Ask the page to fill the screen, or to leave it; a browser grants it only after a key or a click."
        (returns VECTOR "The window")
        (sample "(Web fullscreen! win #t)" "win"))
      (Web %set! win (lit fullscreen) on)
      (Web %serve! win)
      (Web %tell! win (if on "fullscreen 1" "fullscreen 0"))
      win)

    (method poll (self)
      (doc "The next event from the page, or nil; the same events as Sdl's poll answers."
        (returns ANY "An event list, or nil")
        (sample "(Web poll)" "('key-down 97 0 0)"))
      (def win (Web %window))
      (if (null? win) ()
        (do (Web %serve! win)
            (let ((events (Web %ref win (lit events))))
              (if (null? events) ()
                (do (Web %set! win (lit events) (rest events))
                    (first events)))))))

    (method post-key! (self (param code INTEGER "An SDL keycode"))
      (doc "Queue a key-down event, as a key pressed on the page would be."
        (returns INTEGER "The code")
        (sample "(Web post-key! 13)" "13"))
      (def win (Web %window))
      (unless (null? win) (Web %queue! win (list (lit key-down) code 0 0)))
      code)

    (method close (self (param win VECTOR "A window from open"))
      (doc "Tell the page the window is closed and close the sockets."
        (returns ANY "nil")
        (sample "(Web close win)" "nil"))
      (Web %send! win 8 "" 0 () 0)
      (Web %drop! win)
      (Socket close (Web %ref win (lit listener)))
      (%set-first! (Web %window-cell) ())
      ())

    ; --- Sound: a stream is a vector of its number, its rate, its channels
    ; and the time, in microseconds, when what was sent to it ends.
    (method %now (self)
      (doc "The wall clock in microseconds."
        (returns INTEGER "Microseconds since the epoch")
        (sample "(Web %now)" "1752861000123456"))
      (def t (Sys time-of-day))
      (+ (* 1000000 (first t)) (rest t)))

    (method %opened (self (param s VECTOR "A stream"))
      (doc "The message that opens a stream on the page."
        (returns STRING "The message")
        (sample "(Web %opened s)" "\"audio-open 1 44100 2\""))
      (Str8 append "audio-open " (Str8 str (Vector ref 0 s)) " "
                   (Str8 str (Vector ref 1 s)) " " (Str8 str (Vector ref 2 s))))

    (method %rate (self (param s VECTOR "A stream"))
      (doc "The stream's bytes a second."
        (returns INTEGER "Bytes a second")
        (sample "(Web %rate s)" "176400"))
      (* 2 (Vector ref 1 s) (Vector ref 2 s)))

    (method audio-open (self (param rate INTEGER "Frames a second, such as 44100")
                             (param chans INTEGER "Channels: 1 or 2"))
      (doc "Open a stream of signed 16-bit frames to the page; nothing is heard until a key or a click has started the page's sound."
        (returns VECTOR "The stream")
        (sample "(Web audio-open 44100 2)" "a stream"))
      (def win (Web %window))
      (when (null? win) (Err raise (lit state) "Web audio-open: no window is open" ()))
      (def id (+ 1 (first (Web %stream-count))))
      (%set-first! (Web %stream-count) id)
      (def s (Vector make 4 0))
      (Vector set! 0 id s)
      (Vector set! 1 rate s)
      (Vector set! 2 chans s)
      (Vector set! 3 (Web %now) s)
      (Web %set! win (lit streams) (pair s (Web %ref win (lit streams))))
      (Web %serve! win)
      (Web %tell! win (Web %opened s))
      s)

    (method audio-put! (self (param s VECTOR "A stream from audio-open")
                             (param buf STRING "Samples, signed 16-bit little-endian, channels interleaved")
                             (param n INTEGER "How many bytes of buf"))
      (doc "Send n bytes of buf to play after what the stream has."
        (returns VECTOR "The stream")
        (sample "(Web audio-put! s buf 4096)" "s"))
      (def win (Web %window))
      (def now (Web %now))
      (def from (if (> (Vector ref 3 s) now) (Vector ref 3 s) now))
      (Vector set! 3 (+ from (int/ (* n 1000000) (Web %rate s))) s)
      (unless (null? win)
        (do (Web %serve! win)
            (let ((head (str-make 3)))
              (ptr-set! (str->ptr head) 0 65 1)
              (ptr-set! (str->ptr head) 1 (Vector ref 0 s) 1)
              (Web %send! win 2 head 2 buf n))))
      s)

    (method audio-queued (self (param s VECTOR "A stream from audio-open"))
      (doc "Bytes sent to the stream and not yet played, by the clock."
        (returns INTEGER "Bytes")
        (sample "(Web audio-queued s)" "8820"))
      (def left (- (Vector ref 3 s) (Web %now)))
      (if (> left 0) (int/ (* left (Web %rate s)) 1000000) 0))

    (method audio-clear! (self (param s VECTOR "A stream from audio-open"))
      (doc "Drop what the stream has not played."
        (returns VECTOR "The stream")
        (sample "(Web audio-clear! s)" "s"))
      (Vector set! 3 (Web %now) s)
      (def win (Web %window))
      (unless (null? win)
        (Web %tell! win (Str8 append "audio-clear " (Str8 str (Vector ref 0 s)))))
      s)

    (method audio-close (self (param s VECTOR "A stream from audio-open"))
      (doc "Release the stream."
        (returns ANY "nil")
        (sample "(Web audio-close s)" "nil"))
      (def win (Web %window))
      (unless (null? win)
        (do (Web %set! win (lit streams) (List filter (fn (_ t) (not (eq? t s))) (Web %ref win (lit streams))))
            (Web %tell! win (Str8 append "audio-close " (Str8 str (Vector ref 0 s))))))
      ())))

(doc (provide x/sys/web Web)
  "A window in a browser tab: (Web open title w h scale) listens for a page, and Sdl's other messages draw to it, play sound on it, and read its keys and gamepads.")
