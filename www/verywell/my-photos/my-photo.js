function imgOnClick(imgSrc, width, height) {
    const w = Math.min(
        (
            (width > 0)
                ? width + 48
                : 600
        ),
        window.screen.width - 32
    );
    const h = Math.min(
        (
            (height > 0)
                ? height + 48
                : 150
        ),
        window.screen.height - 48
    );
    const l = 22;
    const t = 15;
    window.imgview_src = imgSrc;
    window.imgview_width = width;
    window.imgview_height = height;
    window.open("imgview.htm", "_blank",
        "width=" + w
        + ",height=" + h
        + ",left=" + l
        + ",top=" + t
        + ",status=no,toolbar=no,"
        + "menubar=no,scrollbars=yes,resizable=yes,location=no");
    return false;
}