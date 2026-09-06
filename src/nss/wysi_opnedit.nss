#include "wysi_editor"

void main () {
  SendMessageToPC(GetFirstPC(), "opening?");
  OpenEditor(GetFirstPC());
}
