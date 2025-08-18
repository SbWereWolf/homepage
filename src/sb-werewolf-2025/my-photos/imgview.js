function docReady(fn) {
    if (
        document.readyState === "complete"
        || document.readyState === "interactive"
    ) {
        setTimeout(fn, 100);
    } else {
        document.addEventListener("DOMContentLoaded", fn);
    }
}

docReady(function () {
    let img = document.createElement('img');
    img.src = window.opener.imgview_src;
    img.width = window.opener.imgview_width;
    img.height = window.opener.imgview_height;
    document.getElementById('frame').appendChild(img);
});