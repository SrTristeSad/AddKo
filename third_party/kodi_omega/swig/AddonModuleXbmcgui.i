/*
 *  Copyright (C) 2005-2018 Team Kodi
 *  This file is part of Kodi - https://kodi.tv
 *
 *  SPDX-License-Identifier: GPL-2.0-or-later
 *  See LICENSES/README.md for more information.
 */

%module(directors="1") xbmcgui

%{
#if defined(TARGET_WINDOWS)
#  include <windows.h>
#endif

#include "interfaces/legacy/Dialog.h"
#include "interfaces/legacy/ModuleXbmcgui.h"
#include "interfaces/legacy/Control.h"
#include "interfaces/legacy/Window.h"
#include "interfaces/legacy/WindowDialog.h"
#include "interfaces/legacy/Dialog.h"
#include "interfaces/legacy/WindowXML.h"
#include "input/actions/ActionIDs.h"
#include "input/keyboard/KeyIDs.h"

using namespace XBMCAddon;
using namespace xbmcgui;

#if defined(__GNUG__)
#pragma GCC diagnostic ignored "-Wstrict-aliasing"
#endif

%}

%feature("knownbasetypes") XBMCAddon::xbmcgui "AddonClass,AddonCallback"
%feature("knownapitypes") XBMCAddon::xbmcgui "XBMCAddon::xbmc::InfoTagVideo,xbmc::InfoTagMusic,xbmc::InfoTagPicture,xbmc::InfoTagGame"

%include "interfaces/legacy/swighelper.h"
%include "interfaces/legacy/AddonString.h"
%include "interfaces/legacy/ModuleXbmcgui.h"
%include "interfaces/legacy/Exception.h"
%include "interfaces/legacy/Dictionary.h"
%include "interfaces/legacy/ListItem.h"
%include "interfaces/legacy/Control.h"
%include "interfaces/legacy/Dialog.h"

%feature("python:nokwds") XBMCAddon::xbmcgui::Dialog::Dialog "true"
%feature("python:nokwds") XBMCAddon::xbmcgui::Window::Window "true"
%feature("python:nokwds") XBMCAddon::xbmcgui::WindowXML::WindowXML "true"
%feature("python:nokwds") XBMCAddon::xbmcgui::WindowXMLDialog::WindowXMLDialog "true"
%feature("python:nokwds") XBMCAddon::xbmcgui::WindowDialog::WindowDialog "true"

%feature("director") Window;
%feature("director") WindowDialog;
%feature("director") WindowXML;
%feature("director") WindowXMLDialog;

%include "interfaces/legacy/Window.h"
%include "interfaces/legacy/WindowDialog.h"
%include "interfaces/legacy/Dialog.h"
%include "interfaces/legacy/WindowXML.h"
%include "input/actions/ActionIDs.h"
%include "input/keyboard/KeyIDs.h"
