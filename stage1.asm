;;
;	Definations 
;;
%define PRGADDR 0x7c00
%define DAPADDR 0x1000
%define DISKADDR 0x2000

;;
;	Bits and Org
;;
[bits 16]
[org PRGADDR]

fake_start:
	jmp short real_start ;Jump to real program start 
	nop ; no operation 

;;
; Info: we skip the BPB bytes for two reasons:
; First it makes us compatiable with MBRs that contain an BPB 
; Second some BIOS have bugs related to the BPB bytes thus we skip 
; those potentially buggy bytes 
;;
bpb:
	times (90 - ($ - $$)) db 0x00 ;Skip the BPB bytes 
.end:

;;
; Info: we set each segment register we are going to be using
; to zero as we can't be sure the BIOS has done this for us 
; and could affect how our code loads data and jumps to code 
;;
real_start: 
	cli ;clear intterupts 
	xor ax,ax ;xor out AX register
	mov ds,ax ;ds = 0 
	mov ss,ax ;ss = 0 
	mov es,ax ;es = 0 
	;Skip setting GS and FS as we don't use them here 
	;and we need to save bytes 
	
	cld ;clear the direction flag 

	mov sp,PRGADDR

	;Set the CS register to 0 by far jumping to .set_cs
	;and jump to low start
	jmp 0x0000:.set_cs

.set_cs:
	sti ;We are now at 0x0000:0x06**
	mov byte[disk],dl
	mov ah,0x41
	mov bx,0x55aa
	int 0x13 
	jc error.disk_ext_features_func_error
	cmp bx,0xaa55 
	jne error.disk_ext_features_no_support

;;
; Future plan bipass stage 2 limit of 64KB
; Plan 1:
; Increase the segment selectors when the offset overflows (but this
; isn't great as if the sector size is not cleanly divisible by the limit size 
; it likely wouldn't overflow cleanly)
; 
; Plan 2: 
; Implment a form of compression so MBR loads stage 2 loader decompressor and stage 2 
; Then transfers control to the decompressor program to decompress stage 2(in 32bit mode) 
; then finally stage 2 decompressor passes control to the newly decompressed stage 2.
; Allowing for stage 2 to be decompressed into 32bit address space of RAM.
; 
; Plan 3: 
; Keep 64KB limit but means stage 2 is very limited as it needs to remain below 64KB in 
; size which may be hard to do especially as more features are added.
;;
read_disk:
	mov word[DAPADDR],0x0010 ;Size of packet 
	mov word[DAPADDR+0x02],0x01 ;Number of blocks to transfer 
	mov word[DAPADDR+0x04],0x0000 ;offset 
	mov word[DAPADDR+0x06],0x1000 ;segment
	mov eax,dword[stage2_lba]
	mov dword[DAPADDR+0x08],eax ; 
	mov eax,dword[stage2_lba+4]
	mov dword[DAPADDR+12],eax 
	mov ah,0x42
	mov dl,byte[disk]
	mov si,DAPADDR
	int 0x13 
	
	jc error.disk_read
	jmp 0x1000:0000
jmp end

	

;Byte effcient way to print error codes out 
;Rather than printing strings 
;0 - disk ext function is invalid 
;1 - disk ext features not supported 
;2 - disk read error
error:
	.disk_read: 
	inc byte[error_code]
	.disk_ext_features_no_support:
	inc byte[error_code]
	.disk_ext_features_func_error:

.print_error_code:
	mov al,byte[error_code] ;Load in error code char 
	mov ah,0x0e ;Teletype output 
	xor bx,bx ;xor out BX 
	int 0x10 ;Call intterupt 

end:
	cli 
	hlt 
	jmp end


;;
; Data and padding
;;
disk: db 0x00 
error_code: db '0'

times (430 - ($ - $$)) db 0x00 

stage2_sz: dw 0x0000 
stage2_lba: dq 0x0001

;We are going to avoid using these bytes on the off
;chance some software overwrites our MBR with this data.
;But they are free to use if we need 6 more bytes
dd 0x00000000 ;Optional Disk ID Signature 
dw 0x0000 ;Optional Reserved

times (510 - ($ - $$)) db 0x00 ;Pad to 510 byte 
dw 0xaa55

stage2_start:
	mov ah,0x0e
	mov al,'S'
	xor bx,bx
	int 0x10
	mov ah,0x0e
	mov al,'2'
	xor bx,bx
	int 0x10


times (1024 - ($ - $$)) db 0x00 
