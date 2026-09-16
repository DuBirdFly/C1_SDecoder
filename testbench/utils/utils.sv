package utils;

    function automatic string color_msg(
        // attribute: 0: Normal, 1: Bold, 2: Dim, 3: Italic, 4: Underline, 5: Blink, 7: Reverse, 8: Hidden
        int attr,
        // foreground: 30: Black, 31: Red, 32: Green, 33: Yellow, 34: Blue, 35: Magenta, 36: Cyan, 37: White, 38/39: Default
        int fg,
        // background: 40: Black, 41: Red, 42: Green, 43: Yellow, 44: Blue, 45: Magenta, 46: Cyan, 47: White, 48/49: Default
        int bg,
        string msg
    );
        return $sformatf("\033[%0d;%0d;%0dm%s\033[0m", attr, fg, bg, msg);
    endfunction

    function automatic logic [31:0] get_bit_field (
        input logic [31:0] data,
        input int offset,
        input int width
    );
        logic [31:0] mask;

        if (offset < 0 || offset > 31 || width < 1 || width > 32 || (offset + width) > 32) begin
            $fatal(1, "[FATAL] get_bit_field: 非法参数: offset=%0d, width=%0d", offset, width);
        end

        mask = (32'hFFFFFFFF >> (32 - width)) << offset;
        return (data & mask) >> offset;

    endfunction

    function automatic logic [31:0] set_bit_field (
        input logic [31:0] data,
        input int offset,
        input int width,
        input logic [31:0] value
    );
        logic [31:0] mask;

        if (offset < 0 || offset > 31 || width < 1 || width > 32 || (offset + width) > 32) begin
            $fatal(1, "[FATAL] set_bit_field: 非法参数: offset=%0d, width=%0d", offset, width);
        end

        // value 超出字段宽度 (width) 时，多余高位会被截断，给出 warning 但不 stop
        if (width < 32 && (value >> width) != 0) begin
            $warning(
                "[WARN] set_bit_field: value=0x%h 超出字段宽度 (width=%0d, offset=%0d), 多余高位将被截断",
                value, width, offset
            );
        end

        mask = (32'hFFFFFFFF >> (32 - width)) << offset;
        return (data & ~mask) | ((value << offset) & mask);
    
    endfunction

endpackage
