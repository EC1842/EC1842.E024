;==============================================================================
;  EGACHK - EGA index register check for the EC-1842 PC (EC1842.E024 adapter)
;  Copyright (C) 2026 A.V.L.
;
;  This program is free software: you can redistribute it and/or modify
;  it under the terms of the GNU General Public License version 3 as
;  published by the Free Software Foundation.
;
;  This program is distributed in the hope that it will be useful,
;  but WITHOUT ANY WARRANTY; without even the implied warranty of
;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;  GNU General Public License for more details.
;
;  You should have received a copy of the GNU General Public License
;  along with this program.  If not, see <https://www.gnu.org/licenses/>.
;==============================================================================
;  EGACHK 1.02 - сбивают ли обращения к НГМД/НМД индексные регистры ЕГА.
;
;  Драйвер EGA.DRV Виндоус 3.0/3.1 ставит индекс секвенсора (3C4h) = 2 (маска
;  плоскостей) и индекс графического контроллера (3CEh) = 8 (маска битов)
;  ОДИН РАЗ, а дальше пишет только данные в 3C5h/3CFh. Если что-то меняет
;  индекс 3C4h, маски плоскостей (0..0Fh) попадают в регистр сброса (0) или
;  синхронизации (1) секвенсора - развёртка срывается. BIOS так не делает:
;  он всегда пишет индекс вместе с данными (OUT DX,AX), поэтому в ДОС всё цело.
;
;  Программа ставит режим 10h (640x350x16), индексы 2 и 8, как у драйвера,
;  выполняет действие (обращение INT 13h к НГМД/НМД, запись в порты НГМД/IDE)
;  и проверяет через видеопамять, остались ли индексы на месте:
;    GC:  пишем 00 в 3CFh (маска битов = 0, если индекс 8), читаем A000:2 (защёлки
;         := нули) и пишем туда FF;
;         если байт в памяти изменился - индекс 3CEh уже не 8.
;    SEQ: пишем 03 в 3C5h (плоскости 0,1, если индекс 2) и байт FF в A000:4;
;         если плоскость 2 изменилась - индекс 3C4h уже не 2.
;  После каждой проверки регистры секвенсора и ГК выставляются заново.
;
;  Итог по каждому действию: OK / SEQ (сбит индекс 3C4h) / GC (сбит 3CEh).
;  Запускать в ДОС без Виндоус; резидентные драйверы (мышь!) лучше выгрузить,
;  затем повторить с ними - так видно, кто виноват: железо или резидент.
;==============================================================================
CODE    SEGMENT
        ASSUME  CS:CODE, DS:CODE
        ORG     100h
start:  jmp     main
        DB      0
oldmode DB      3
res_gc  DB      0                               ; итог последней проверки
res_sq  DB      0
drv     DB      0
nfail   DW      0
nfl     DW      0
;------------------------------------------------------------------------------
main:   mov     ah,0Fh
        int     10h
        mov     oldmode,al
        mov     dx,OFFSET m_hello
        mov     ah,9
        int     21h
        mov     ax,0010h                        ; 640x350x16
        int     10h
        call    regs_std
;  1. без действий
        call    arm
        call    check
        mov     al,0
        call    keep
;  2. сброс НГМД (INT 13h AH=0, DL=0)
        call    arm
        mov     ah,0
        mov     dl,0
        int     13h
        call    check
        mov     al,1
        call    keep
;  3. чтение сектора A: (INT 13h AH=2)
        call    arm
        call    rd_flop
        call    check
        mov     al,2
        call    keep
;  4. чтение сектора НМД 80h
        call    arm
        call    rd_hdd
        call    check
        mov     al,3
        call    keep
;  5. порты НГМД: 3F2h (DOR 0Ch - без мотора), 3F7h (скорость 0)
        call    arm
        mov     dx,3F2h
        mov     al,0Ch
        out     dx,al
        call    check
        mov     al,4
        call    keep
        call    arm
        mov     dx,3F7h
        mov     al,0
        out     dx,al
        call    check
        mov     al,5
        call    keep
;  6. порты IDE1: 1F2h..1F6h (параметры без команды), 3F6h (управление 08h)
        call    arm
        mov     dx,1F2h
        mov     al,1
        out     dx,al
        inc     dx                              ; 1F3
        out     dx,al
        inc     dx                              ; 1F4
        mov     al,0
        out     dx,al
        inc     dx                              ; 1F5
        out     dx,al
        inc     dx                              ; 1F6
        mov     al,0A0h
        out     dx,al
        call    check
        mov     al,6
        call    keep
        call    arm
        mov     dx,3F6h
        mov     al,08h
        out     dx,al
        call    check
        mov     al,7
        call    keep
;  7. порты IDE2: 172h..176h, 376h
        call    arm
        mov     dx,172h
        mov     al,1
        out     dx,al
        inc     dx
        out     dx,al
        inc     dx
        mov     al,0
        out     dx,al
        inc     dx
        out     dx,al
        inc     dx
        mov     al,0A0h
        out     dx,al
        call    check
        mov     al,8
        call    keep
        call    arm
        mov     dx,376h
        mov     al,08h
        out     dx,al
        call    check
        mov     al,9
        call    keep
;  8. индекс CRTC 3D4h = 0Fh (так делает BIOS при каждом выводе)
        call    arm
        mov     dx,3D4h
        mov     al,0Fh
        out     dx,al
        call    check
        mov     al,10
        call    keep
;  контроль метода: нарочно сбить индексы - должно быть SEQ / GC
        call    arm
        mov     dx,3C4h
        mov     al,1
        out     dx,al
        call    check
        mov     al,11
        call    keep
        call    arm
        mov     dx,3CEh
        mov     al,5
        out     dx,al
        call    check
        mov     al,12
        call    keep
;  9. 20 чтений НГМД подряд: сколько раз сбился индекс
        mov     nfail,0
        mov     cx,20
m9:     push    cx
        call    arm
        call    rd_flop
        call    check
        mov     al,res_gc
        or      al,res_sq
        jz      m9n
        inc     nfail
m9n:    pop     cx
        loop    m9
;  10. 20 чтений НМД подряд
        mov     ax,nfail
        mov     nfl,ax
        mov     nfail,0
        mov     cx,20
m10:    push    cx
        call    arm
        call    rd_hdd
        call    check
        mov     al,res_gc
        or      al,res_sq
        jz      m10n
        inc     nfail
m10n:   pop     cx
        loop    m10
        push    nfail
        push    nfl
;  11. зондирование портов: какие адреса задевают индекс 3C4h (запись 1 в порт)
;      и данные 3C5h (запись 3 в порт+1). КВП (0C4h), таймер, контроллеры
;      прерываний, клавиатура (64h), синхронизатор (0E4h) пропущены.
        mov     si,OFFSET ports
        mov     di,OFFSET presult
p11:    mov     dx,[si]
        or      dx,dx
        jz      p11x
        push    si
        push    di
        call    arm
        pop     di
        pop     si
        mov     dx,[si]
        mov     al,1
        out     dx,al                           ; порт := 1 (индекс?)
        push    si
        push    di
        call    check
        pop     di
        pop     si
        mov     al,res_sq
        mov     [di],al
        push    si
        push    di
        call    arm
        pop     di
        pop     si
        mov     dx,[si]
        inc     dx
        mov     al,3
        out     dx,al                           ; порт+1 := 3 (данные - маска плоскостей?)
        push    si
        push    di
        call    chk_msk
        pop     di
        pop     si
        or      [di],al
        inc     si
        inc     si
        inc     di
        jmp     short p11
p11x:   mov     ah,0                            ; сброс НГМД после записи в 3F4h
        mov     dl,0
        int     13h
;  назад в текст и отчёт
        mov     al,oldmode
        xor     ah,ah
        int     10h
        mov     dx,OFFSET m_hdr
        mov     ah,9
        int     21h
        mov     si,OFFSET names
        mov     di,OFFSET results
        mov     cx,13
rep1:   push    cx
        mov     dx,si
        mov     ah,9
        int     21h
        mov     al,[di]
        call    verdict
        pop     cx
        inc     di
add_nm: lodsb
        cmp     al,'$'
        jne     add_nm
        loop    rep1
        mov     dx,OFFSET m_f20
        mov     ah,9
        int     21h
        pop     ax
        call    dec2
        mov     dx,OFFSET m_h20
        mov     ah,9
        int     21h
        pop     ax
        call    dec2
        mov     dx,OFFSET m_p11
        mov     ah,9
        int     21h
        mov     si,OFFSET ports
        mov     di,OFFSET presult
rep2:   mov     dx,[si]
        or      dx,dx
        jz      rep2x
        mov     al,[di]
        or      al,al
        jz      rep2n
        push    ax
        mov     ax,dx
        call    hex3
        pop     ax
        push    ax
        mov     dx,OFFSET m_pi
        test    al,1
        jnz     rep2p
        mov     dx,OFFSET m_sp
rep2p:  mov     ah,9
        int     21h
        pop     ax
        mov     dx,OFFSET m_pd
        test    al,2
        jnz     rep2q
        mov     dx,OFFSET m_sp
rep2q:  mov     ah,9
        int     21h
        mov     dx,OFFSET m_nl
        mov     ah,9
        int     21h
rep2n:  inc     si
        inc     si
        inc     di
        jmp     short rep2
rep2x:  mov     dx,OFFSET m_end
        mov     ah,9
        int     21h
        mov     ax,4C00h
        int     21h
;------------------------------------------------------------------------------
;  verdict: AL - код результата: 0 OK, бит0 - GC сбит, бит1 - SEQ сбит
verdict PROC NEAR
        mov     dx,OFFSET m_ok
        test    al,3
        jz      v_p
        mov     dx,OFFSET m_gc
        test    al,1
        jnz     v_p
        mov     dx,OFFSET m_sq
v_p:    push    ax
        mov     ah,9
        int     21h
        pop     ax
        test    al,3
        jz      v_x
        and     al,3
        cmp     al,3
        jne     v_x
        mov     dx,OFFSET m_sq                  ; сбиты оба: допечатать SEQ
        mov     ah,9
        int     21h
v_x:    mov     dx,OFFSET m_nl
        mov     ah,9
        int     21h
        ret
verdict ENDP
;  keep: AL - номер действия; записать res_gc/res_sq в results[AL]
keep    PROC NEAR
        xor     ah,ah
        mov     bx,ax
        mov     al,res_sq
        shl     al,1
        or      al,res_gc
        mov     results[bx],al
        ret
keep    ENDP
;  dec2: напечатать AX (0..99)
dec2    PROC NEAR
        xor     dx,dx
        mov     cx,10
        div     cx
        push    dx
        add     al,'0'
        mov     dl,al
        mov     ah,2
        int     21h
        pop     dx
        add     dl,'0'
        mov     ah,2
        int     21h
        ret
dec2    ENDP
;------------------------------------------------------------------------------
;  rd_flop / rd_hdd: INT 13h AH=2, 1 сектор, цилиндр 0, головка 0, сектор 1
rd_flop PROC NEAR
        mov     dl,0
        jmp     short rd_x
rd_hdd: mov     dl,80h
rd_x:   push    es
        push    cs
        pop     es
        mov     bx,OFFSET buf
        mov     ax,0201h
        mov     cx,0001h
        mov     dh,0
        int     13h
        pop     es
        ret
rd_flop ENDP
;------------------------------------------------------------------------------
;  regs_std: регистры секвенсора и ГК режима 10h заново (индексы: SEQ 4, GC 8)
regs_std PROC NEAR
        mov     dx,3C4h
        mov     ax,0100h                        ; 1: сброс (синхронный)
        out     dx,ax
        mov     ax,0101h                        ; синхронизация: 8 точек
        out     dx,ax
        mov     ax,0F02h                        ; маска плоскостей
        out     dx,ax
        mov     ax,0003h                        ; знакогенератор
        out     dx,ax
        mov     ax,0604h                        ; память: расширенная, не чёт/нечет
        out     dx,ax
        mov     ax,0300h                        ; снять сброс
        out     dx,ax
        mov     dx,3CEh
        mov     ax,0000h                        ; set/reset
        out     dx,ax
        mov     ax,0001h                        ; enable set/reset
        out     dx,ax
        mov     ax,0002h                        ; сравнение
        out     dx,ax
        mov     ax,0003h                        ; сдвиг/функция
        out     dx,ax
        mov     ax,0004h                        ; чтение: плоскость 0
        out     dx,ax
        mov     ax,0005h                        ; режим 0
        out     dx,ax
        mov     ax,0506h                        ; A000h, графика
        out     dx,ax
        mov     ax,0F07h                        ; безразличные
        out     dx,ax
        mov     ax,0FF08h                       ; маска битов
        out     dx,ax
        ret
regs_std ENDP
;  arm: очистить A000:0..7 во всех плоскостях и оставить индексы как у драйвера
arm     PROC NEAR
        call    regs_std
        push    es
        mov     ax,0A000h
        mov     es,ax
        xor     di,di
        xor     ax,ax
        mov     cx,4
        rep stosw
        pop     es
        mov     dx,3C4h                         ; индекс SEQ = 2, данные 0Fh
        mov     ax,0F02h
        out     dx,ax
        mov     dx,3CEh                         ; индекс GC = 8, данные FFh
        mov     ax,0FF08h
        out     dx,ax
        ret
arm     ENDP
;  check: res_gc := 1, если индекс 3CEh ушёл с 8; res_sq := 1, если 3C4h ушёл с 2
check   PROC NEAR
        push    es
        mov     ax,0A000h
        mov     es,ax
        mov     res_gc,0
        mov     res_sq,0
;  GC: 3CFh := 0 (маска битов 0 - запись ничего не меняет)
        mov     dx,3CFh
        mov     al,0
        out     dx,al
        mov     al,es:[2]                       ; защёлки := нули (маска 0 пишет защёлки)
        mov     BYTE PTR es:[2],0FFh
        mov     al,es:[2]                       ; чтение: плоскость 0
        or      al,al
        jz      c_gc_ok
        mov     res_gc,1
c_gc_ok:
;  SEQ: 3C5h := 3 (плоскости 0 и 1); плоскость 2 меняться не должна
        mov     dx,3C5h
        mov     al,3
        out     dx,al
        mov     dx,3CEh                         ; маска битов - снова FF
        mov     ax,0FF08h
        out     dx,ax
        mov     BYTE PTR es:[4],0FFh
        mov     ax,0204h                        ; чтение: плоскость 2
        out     dx,ax
        mov     al,es:[4]
        or      al,al
        jz      c_sq_ok
        mov     res_sq,1
c_sq_ok:
        pop     es
        call    regs_std
        ret
check   ENDP
;  chk_msk: AL := 2, если маска плоскостей (3C5h) стала 3 без нашей записи в неё
;  (чужая запись попала в данные секвенсора), иначе 0. Индекс остаётся 2.
chk_msk PROC NEAR
        push    es
        mov     ax,0A000h
        mov     es,ax
        mov     BYTE PTR es:[6],0FFh            ; маска 0Fh: все плоскости; 03h: только 0,1
        mov     dx,3CEh
        mov     ax,0204h                        ; чтение: плоскость 2
        out     dx,ax
        mov     al,es:[6]
        pop     es
        push    ax
        call    regs_std
        pop     ax
        or      al,al
        mov     al,0
        jnz     cm_x
        mov     al,2
cm_x:   ret
chk_msk ENDP
;  hex3: напечатать "  xxxh " для AX
hex3    PROC NEAR
        push    ax
        mov     dx,OFFSET m_sp2
        mov     ah,9
        int     21h
        pop     ax
        mov     cl,4
        shl     ax,cl                           ; разряды 11-8 - в старшую тетраду
        mov     cx,3
h3_l:   rol     ax,1
        rol     ax,1
        rol     ax,1
        rol     ax,1
        push    ax
        and     al,0Fh
        add     al,'0'
        cmp     al,'9'
        jbe     h3_p
        add     al,7
h3_p:   mov     dl,al
        mov     ah,2
        int     21h
        pop     ax
        loop    h3_l
        mov     dx,OFFSET m_h
        mov     ah,9
        int     21h
        ret
hex3    ENDP
m_h     DB      'h: $'
;------------------------------------------------------------------------------
ports   DW      004h,084h,0C4h                  ; 0C4h - КВП (база): не под монитором 286 режима!
        DW      104h,114h,124h,134h,144h,154h,164h,174h,184h,194h,1A4h,1B4h
        DW      1C4h,1D4h,1E4h,1F4h
        DW      204h,244h,254h,264h,274h,284h,294h,2A4h,2B4h,2C4h,2D4h,2E4h,2F4h
        DW      304h,314h,344h,354h,374h,394h,3B4h,3D4h,3E4h,3F4h
        DW      0
presult DB      64 DUP (0)
m_p11   DB      13,10,'Porty, zadevayushchie EGA (indeks 3C4h / dannye 3C5h):',13,10,'$'
m_pi    DB      'INDEKS $'
m_pd    DB      'DANNYE $'
m_sp    DB      '       $'
m_sp2   DB      '  port $'
m_hello DB      'EGACHK 1.02: indeksy EGA (3C4h=2, 3CEh=8) posle obrashcheniy k diskam',13,10,'$'
m_hdr   DB      13,10,'EGACHK itog:',13,10,'$'
names   DB      '  bez deystviy          $'
        DB      '  INT 13h sbros NGMD    $'
        DB      '  INT 13h chtenie A:    $'
        DB      '  INT 13h chtenie 80h   $'
        DB      '  OUT 3F2h,0Ch          $'
        DB      '  OUT 3F7h,0            $'
        DB      '  OUT 1F2h..1F6h        $'
        DB      '  OUT 3F6h,08h          $'
        DB      '  OUT 172h..176h        $'
        DB      '  OUT 376h,08h          $'
        DB      '  OUT 3D4h,0Fh          $'
        DB      '  kontrol: OUT 3C4h,1   $'
        DB      '  kontrol: OUT 3CEh,5   $'
m_ok    DB      'OK$'
m_gc    DB      'GC sbit $'
m_sq    DB      'SEQ sbit $'
m_nl    DB      13,10,'$'
m_f20   DB      '  20 chteniy A:  sboev: $'
m_h20   DB      13,10,'  20 chteniy 80h sboev: $'
m_end   DB      13,10,'EGACHK konec',13,10,'$'
results DB      16 DUP (0)
buf     DB      0
CODE    ENDS
        END     start
