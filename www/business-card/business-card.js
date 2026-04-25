const imageDialog = document.getElementById("imageDialog");
const imageDialogImage = document.getElementById("imageDialogImage");
const closeDialogButton = imageDialog?.querySelector(".image-dialog__close");
let lastImageTrigger = null;

function closeImageDialog() {
  imageDialog.close();
  lastImageTrigger?.focus();
}

if (
  imageDialog &&
  imageDialogImage &&
  closeDialogButton &&
  typeof imageDialog.showModal === "function"
) {
  document.querySelectorAll(".image-trigger").forEach((button) => {
    button.addEventListener("click", () => {
      lastImageTrigger = button;
      imageDialogImage.src = button.dataset.fullSrc;
      imageDialogImage.alt = button.dataset.alt;
      imageDialog.showModal();
      closeDialogButton.focus();
    });
  });

  closeDialogButton.addEventListener("click", closeImageDialog);
  imageDialog.addEventListener("click", (event) => {
    if (event.target === imageDialog) {
      closeImageDialog();
    }
  });
}
