.text                           # IMPORTANT: subsequent stuff is executable
.global  set_tod_from_ports
## ENTRY POINT FOR REQUIRED FUNCTION
set_tod_from_ports:

        movl    TIME_OF_DAY_PORT(%rip), %eax    # move TODP value into %eax

        cmpl    $0,%eax                         # less than 0
        jl      .BADTIME
        cmpl    $1382400,%eax                   # more than 16 * seconds in a day
        jg      .BADTIME

        cqto                                    # preping for division
        movl    $16,%r8d
        idivl   %r8d                            # divided by 16
                                             
        cmpl    $7,%edx
        jg     .ROUNDUP                         # if remainder is >= 8, we round up, otherwise we move on

        jmp     .DIVIDING

.BADTIME:
        movl    $1,%eax                         # return 1
        ret 

.ROUNDUP:
        addl    $1,%eax                         # add 1 to %eax

.DIVIDING:
        movl    %eax,0(%rdi)                    # %eax is now equal to total seconds, so we assign it to day_secs
        
        # the whole rapid fire division fiasco
        cqto                                    # preping for division
        movl    $3600,%r8d                      # %r8d = 3600, the amount of seconds in an hour
        idivl   %r8d                            # divided by 3600
        movw    %ax,8(%rdi)                     # assigning %ax to tod->time_hours


        movl    %edx,%eax                       # making the remainder from previous division the new numerator
        cqto                                    # preping for division
        movl    $60,%r8d                      
        idivl   %r8d                            # divided by 60
        movw    %ax,6(%rdi)                     # assigning %ax to tod->time_mins

        movw    %dx,4(%rdi)                     # assigning %dx, the remainder, to tod->time_secs

        movb    $1,10(%rdi)                     # setting AM as the default
        cmpw    $11,8(%rdi)                     # checking if hour > 11 i.e. >= 12 to see if its PM or AM
        jg      .PM

        jmp     .FORMAT1


        ## *** PM, AFTER12, and 0_OR_12 are all products of "if statements" ***
.PM:
        ## came here because tod->time_hours >= 12
        movb    $2,10(%rdi)
        jmp     .FORMAT1

.AFTER12:
        ## came here because tod->time_hours > 12
        subw    $12,8(%rdi)
        jmp     .FORMAT2

.0_OR_12:
        ## came here because tod->time_hours == 12 || tod->time_hours == 0
        movw    $12,8(%rdi)
        movl    $0,%eax
        ret

.FORMAT1: 
        ## first step of formatting, subtracting 12 if hour > 12
        cmpw    $12,8(%rdi)
        jg      .AFTER12

.FORMAT2:
        ## second step of formatting, correcting the hour in the case its 0 or 12 
        cmpw    $12,8(%rdi)
        je      .0_OR_12

        cmpw    $0,8(%rdi)
        je      .0_OR_12

        movl    $0,%eax
        ret

### Data area associated with the next function
.data                           # IMPORTANT: use .data directive for data section

masks:                       
        .int 0b1110111          # 0   
        .int 0b0100100          # 1
        .int 0b1011101          # 2
        .int 0b1101101          # 3
        .int 0b0101110          # 4
        .int 0b1101011          # 5
        .int 0b1111011          # 6
        .int 0b0100101          # 7
        .int 0b1111111          # 8
        .int 0b1101111          # 9


.text                           # IMPORTANT: switch back to executable code after .data section
.global  set_display_from_tod

## ENTRY POINT FOR REQUIRED FUNCTION
set_display_from_tod:
        
        movq    %rsi,%r10                       # %r10w holds tod.time_hours
        cmpw    $0,%r10w                        # validity checks for hours
        js      .INVALID_FIELD                  # < 0
        cmpw    $12,%r10w
        ja      .INVALID_FIELD                  # > 12
        ## the rest of my validity tests are in order as the constructing of the display int occurs
        ## if an issue is found, it will be resolved there.

        movq    %rdx,%r11                       # moving display pointer over to %r11
        movl    $0,(%r11)                       # *display = 0


        cmpw    $9,%r10w                        # if hour >= 10, jump to function that sets the ten's place of hour
        ja      .HOUR_TENS_PLACE

        jmp     .HOUR_ONES_PLACE                # else head to function that sets one's place of hour instead

.INVALID_FIELD:
        movl    $1,%eax
        ret

.HOUR_TENS_PLACE:
        ## setting the bits for the ten's place of the hour
        movq    $0b0100100, %r9                 # move binary for 1 into %r9
        salq    $21,%r9                         # shift left by 21 bits
        orl     %r9d,(%r11)                     # *display = *display | %r9
        jmp     .HOUR_ONES_PLACE                # jumping to the setting of the one's place of the hour

.HOUR_ONES_PLACE:
        ## setting the bits for the one's place of the hour
        cqto                                    # prep for division
        movw    %r10w,%ax                       # move hour into %ax
        movw    $10,%r8w                        # move 10 into %r8w
        idivw   %r8w                            # divide hour by 10
                                                # remainder (%dx) = ones place of hour
        leaq    masks(%rip),%rcx                # load ea of masks array into %rcx
        movl    (%rcx,%rdx,4), %r8d             # %r8d = masks[%rdx]
        salq    $14,%r8                         # shift left 14
        orl     %r8d,(%r11)                     # setting bits for the one's place of hour

        jmp     .SET_AMPM                       # jumping to the setting of the ampm bits

.SET_AMPM:
        sarq    $16,%r10                        # shift right by 16 bits
        andq    $0xF,%r10                       # %r10w holds tod.ampm

        cmpw    $2,%r10w                        # validity cheks for ampm
        ja      .INVALID_FIELD                  # > 2
        cmpw    $1,%r10w
        jb      .INVALID_FIELD                  # < 1

        cmpw    $1,%r10w
        ja      .PM_BITS                        # go to .PM to set bits as PM (if tod.ampm == 2)

        movq    $0b01,%r10                      # making shift holder
        salq    $28,%r10                        # shift left 28 (this represents 1, which will be the default)
        orl     %r10d,(%r11)                    # *display = *display | (0b01 << 28)
        jmp     .SET_MINS                       # jumping to the setting of the ten's place of the minutes


.PM_BITS:
        movq    $0b10,%r10                      # making shift holder
        salq    $28,%r10                        # shift left 28
        orl     %r10d,(%r11)                    # *display = *display | (0b10 << 28)
        jmp     .SET_MINS                       # jumping to the setting of the ten's place of the minutes

.SET_MINS:
        movq    %rdi,%r10              
        sarq    $32,%r10                        # shift right 32
        andq    $0xFFFF,%r10                    # %r10 now holds tod.day_secs

        cmpw    $59,%r10w                       # validity cheks for secs
        ja      .INVALID_FIELD                  # > 59
        cmpw    $0,%r10w
        js      .INVALID_FIELD                  # < 0

        movq    %rdi,%r10
        sarq    $48,%r10                        # shift right 48
        andq    $0xFFFF,%r10                    # %r10 now holds tod.day_mins

        cmpw    $59,%r10w                       # validity cheks for mins
        ja      .INVALID_FIELD                  # > 59
        cmpw    $0,%r10w
        js      .INVALID_FIELD                  # < 0

        cqto                                    # prep for division
        movq    %r10,%rax                       # move mins into %ax
        movw    $10,%r8w                        # move 10 into %r8w
        idivw   %r8w                            # divide mins by 10

        leaq    masks(%rip),%rcx 
        movl    (%rcx,%rax,4), %r8d             # %r8d = masks[%rax] 
        salq    $7,%r8
        orl     %r8d,(%r11)                     # set ten's place of minutes bits

        movl    (%rcx,%rdx,4), %r8d             # %r8d = masks[%rdx] 
        salq    $0,%r8
        orl     %r8d,(%r11)                     # set one's place of minutes bits

        movq    %r11,%rdx                       # placing display pointer back into %rdx
        movl    (%r11),%ebx                     # moving display int pointed to by %r11 in to %ebx
        movl    %ebx,(%rdx)                     # making %rdx point to display int

        movl    $0,%eax                
        ret                                     # return 0

.text
.global clock_update
        
## ENTRY POINT FOR REQUIRED FUNCTION
clock_update:
        subq    $40,%rsp                        # extend stack by 40 (16 * 2 + 8)
        movq    %rsp, %rdi
        call    set_tod_from_ports              
        movl    %eax, %r8d                      # passing return value to %r8d
        cmpl    $1,%r8d                         # checking for error
        je      .UPDATE_ERROR

        movq    0(%rsp),%rdi                    # packing part of struct in %rdi
        movq    8(%rsp),%rsi                    # packing rest in %rsi
        leaq   CLOCK_DISPLAY_PORT(%rip),%r10    # %r10 = CLOCK_DISPLAY_PORT
        movq    %r10,%rdx                       # %rdx = &(%r10) --> %rdx = &CLOCK_DISPLAY_PORT

        call    set_display_from_tod  
        movl    %eax, %r8d                      # passing return value to %r8d
        cmpl    $1,%r8d                         # checking for error
        je      .UPDATE_ERROR
        

        addq    $40,%rsp                        # return stack to original state

        movl    $0,%eax                         # return 0
        ret

.UPDATE_ERROR:
        addq    $40,%rsp
        movl    $1,%eax
        ret
