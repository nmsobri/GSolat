package main
import "core:fmt"

import "ocurl"
import "core:c"
import "core:os"
import "core:mem"
import "core:log"
import "core:time"
import "core:bytes"
import "core:strings"
import "core:runtime"
import "core:image/png"
import "core:encoding/json"

import sdl "vendor:sdl2"
import gl "vendor:OpenGL"

import imgui "imgui"
import imsdl "imgui/impl/sdl"
import imgl "imgui/impl/opengl"

DESIRED_GL_MAJOR_VERSION :: 4
DESIRED_GL_MINOR_VERSION :: 5

SIZE: uint = 0
DEFAULT_ZONE :: "PNG01"
API :: "https://www.e-solat.gov.my/index.php?r=esolatApi/takwimsolat&period=month&zone="


Imgui_State :: struct {
  sdl_state:    imsdl.SDL_State,
  opengl_state: imgl.OpenGL_State,
}

Prayer :: struct {
  PrayerTime: []struct {
    Hijri:   string `json:"hijri"`,
    Date:    string `json:"date"`,
    Day:     string `json:"day"`,
    Imsak:   string `json:"imsak"`,
    Fajr:    string `json:"fajr"`,
    Syuruk:  string `json:"syuruk"`,
    Dhuhr:   string `json:"dhuhr"`,
    Asr:     string `json:"asr"`,
    Maghrib: string `json:"maghrib"`,
    Isha:    string `json:"isha"`,
  } `json:"prayerTime"`,
  Status:     string `json:"status"`,
  ServerTime: string `json:"serverTime"`,
  PeriodType: string `json:"periodType"`,
  Lang:       string `json:"lang"`,
  Zone:       string `json:"zone"`,
  Bearing:    string `json:"bearing"`,
}

main :: proc() {
  if err := sdl.Init({.VIDEO}); err != 0 {
    log.debugf("Error during SDL init: (%d)%s", err, sdl.GetError())
    return
  }

  defer sdl.Quit()

  window := sdl.CreateWindow("Solat", 100, 100, 800, 600, {.OPENGL, .MOUSE_FOCUS, .SHOWN, .RESIZABLE})
  if window == nil {
    log.debugf("Error during window creation: %s", sdl.GetError())
    sdl.Quit()
    return
  }

  defer sdl.DestroyWindow(window)

  renderer := sdl.CreateRenderer(window, -1, sdl.RENDERER_ACCELERATED)
  if renderer == nil {
    log.debugf("Error during renderer creation: %s", sdl.GetError())
    sdl.Quit()
    return
  }

  rmask, gmask, bmask, amask: u32

  when ODIN_ENDIAN == .Big {
    rmask = 0xFF000000
    gmask = 0x00FF0000
    bmask = 0x0000FF00
    amask = 0x000000FF
  } else when ODIN_ENDIAN == .Little {
    rmask = 0x000000FF
    gmask = 0x0000FF00
    bmask = 0x00FF0000
    amask = 0xFF000000
  }

  icon_width: i32 = 64
  icon_height: i32 = 64
  icon_data := #load("./../res/kaabah.png")

  icon_img, err := png.load(icon_data)
  defer png.destroy(icon_img)

  surface := sdl.CreateRGBSurfaceFrom(raw_data(bytes.buffer_to_bytes(&icon_img.pixels)), icon_width, icon_height, 32, 256, rmask, gmask, bmask, amask)
  defer sdl.FreeSurface(surface)

  sdl.SetWindowIcon(window, surface)

  // Setting up the OpenGL...
  sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, DESIRED_GL_MAJOR_VERSION)
  sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, DESIRED_GL_MINOR_VERSION)
  sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(sdl.GLprofile.CORE))
  sdl.GL_SetAttribute(.DOUBLEBUFFER, 1)
  sdl.GL_SetAttribute(.DEPTH_SIZE, 24)
  sdl.GL_SetAttribute(.STENCIL_SIZE, 8)

  gl_ctx := sdl.GL_CreateContext(window)

  if gl_ctx == nil {
    log.debugf("Error during window creation: %s", sdl.GetError())
    return
  }

  sdl.GL_MakeCurrent(window, gl_ctx)
  defer sdl.GL_DeleteContext(gl_ctx)

  if sdl.GL_SetSwapInterval(1) != 0 {
    log.debugf("Error during window creation: %s", sdl.GetError())
    return
  }

  gl.load_up_to(DESIRED_GL_MAJOR_VERSION, DESIRED_GL_MINOR_VERSION, sdl.gl_set_proc_address)
  gl.ClearColor(1, 1, 1, 1)

  imgui_state := init_imgui_state(window)

  running := true
  show_demo_window := false
  e := sdl.Event{}

  for running {

    for sdl.PollEvent(&e) {

      imsdl.process_event(e, &imgui_state.sdl_state)

      #partial switch e.type {
      case .QUIT:
        running = false

      case .KEYDOWN:
        if is_key_down(e, .ESCAPE) {
          qe := sdl.Event{}
          qe.type = .QUIT
          sdl.PushEvent(&qe)
        }

        if is_key_down(e, .TAB) {
          io := imgui.get_io()
          if io.want_capture_keyboard == false {
            show_demo_window = true
          }
        }

      }
    }

    imgui_new_frame(window, &imgui_state)
    imgui.new_frame()

    {
      if show_demo_window do imgui.show_demo_window(&show_demo_window)
      main_window()
    }

    imgui.render()

    io := imgui.get_io()
    gl.Viewport(0, 0, i32(io.display_size.x), i32(io.display_size.y))
    gl.Scissor(0, 0, i32(io.display_size.x), i32(io.display_size.y))
    gl.Clear(gl.COLOR_BUFFER_BIT)

    imgl.imgui_render(imgui.get_draw_data(), imgui_state.opengl_state)
    sdl.GL_SwapWindow(window)
  }
}

main_window :: proc() {
  io := imgui.get_io()
  flags: imgui.Window_Flags = .NoDecoration | .AlwaysAutoResize | .NoSavedSettings | .NoFocusOnAppearing | .NoNav | .NoMove

  imgui.set_next_window_pos(imgui.Vec2{0, 0})
  imgui.set_next_window_size(imgui.Vec2{io.display_size.x, io.display_size.y})
  imgui.begin("Main", nil, flags)

  @(static)
  zones_code := [?]string{
    "DEFLT",
    "JHR01",
    "JHR02",
    "JHR03",
    "JHR04",
    "KDH01",
    "KDH02",
    "KDH03",
    "KDH04",
    "KDH05",
    "KDH06",
    "KDH07",
    "KTN01",
    "KTN02",
    "MLK01",
    "NGS01",
    "NGS02",
    "NGS03",
    "PHG01",
    "PHG02",
    "PHG03",
    "PHG04",
    "PHG05",
    "PHG06",
    "PLS01",
    "PNG01",
    "PRK01",
    "PRK02",
    "PRK03",
    "PRK04",
    "PRK05",
    "PRK06",
    "PRK07",
    "SBH01",
    "SBH02",
    "SBH03",
    "SBH04",
    "SBH05",
    "SBH06",
    "SBH07",
    "SBH08",
    "SBH09",
    "SGR01",
    "SGR02",
    "SGR03",
    "SWK01",
    "SWK02",
    "SWK03",
    "SWK04",
    "SWK05",
    "SWK06",
    "SWK07",
    "SWK08",
    "SWK09",
    "TRG01",
    "TRG02",
    "TRG03",
    "TRG04",
    "WLY01",
    "WLY02",
  }

  @(static)
  zones_name := [?]string{
    "Please Select",
    "Pulau Aur dan Pulau Pemanggil",
    "Johor Bahru, Kota Tinggi, Mersing, Kulai",
    "Kluang, Pontian",
    "Batu Pahat, Muar, Segamat, Gemas Johor, Tangkak",
    "Kota Setar, Kubang Pasu, Pokok Sena (Daerah Kecil)",
    "Kuala Muda, Yan, Pendang",
    "Padang Terap, Sik",
    "Baling",
    "Bandar Baharu, Kulim",
    "Langkawi",
    "Puncak Gunung Jerai",
    "Bachok, Kota Bharu, Machang, Pasir Mas, Pasir Puteh, Tanah Merah, Tumpat, Kuala Krai, Mukim Chiku",
    "Gua Musang (Daerah Galas Dan Bertam), Jeli, Jajahan Kecil Lojing",
    "SELURUH NEGERI MELAKA",
    "Tampin, Jempol",
    "Jelebu, Kuala Pilah, Rembau",
    "Port Dickson, Seremban",
    "Pulau Tioman",
    "Kuantan, Pekan, Rompin, Muadzam Shah",
    "Jerantut, Temerloh, Maran, Bera, Chenor, Jengka",
    "Bentong, Lipis, Raub",
    "Genting Sempah, Janda Baik, Bukit Tinggi",
    "Cameron Highlands, Genting Higlands, Bukit Fraser",
    "Kangar, Padang Besar, Arau",
    "Seluruh Negeri Pulau Pinang",
    "Tapah, Slim River, Tanjung Malim",
    "Kuala Kangsar, Sg. Siput , Ipoh, Batu Gajah, Kampar",
    "Lenggong, Pengkalan Hulu, Grik",
    "Temengor, Belum",
    "Kg Gajah, Teluk Intan, Bagan Datuk, Seri Iskandar, Beruas, Parit, Lumut, Sitiawan, Pulau Pangkor",
    "Selama, Taiping, Bagan Serai, Parit Buntar",
    "Bukit Larut",
    "Bahagian Sandakan (Timur), Bukit Garam, Semawang, Temanggong, Tambisan, Bandar Sandakan, Sukau",
    "Beluran, Telupid, Pinangah, Terusan, Kuamut, Bahagian Sandakan (Barat)",
    "Lahad Datu, Silabukan, Kunak, Sahabat, Semporna, Tungku, Bahagian Tawau  (Timur)",
    "Bandar Tawau, Balong, Merotai, Kalabakan, Bahagian Tawau (Barat)",
    "Kudat, Kota Marudu, Pitas, Pulau Banggi, Bahagian Kudat",
    "Gunung Kinabalu",
    "Kota Kinabalu, Ranau, Kota Belud, Tuaran, Penampang, Papar, Putatan, Bahagian Pantai Barat",
    "Pensiangan, Keningau, Tambunan, Nabawan, Bahagian Pendalaman (Atas)",
    "Beaufort, Kuala Penyu, Sipitang, Tenom, Long Pasia, Membakut, Weston, Bahagian Pendalaman (Bawah)",
    "Gombak, Petaling, Sepang, Hulu Langat, Hulu Selangor, S.Alam",
    "Kuala Selangor, Sabak Bernam",
    "Klang, Kuala Langat",
    "Limbang, Lawas, Sundar, Trusan",
    "Miri, Niah, Bekenu, Sibuti, Marudi",
    "Pandan, Belaga, Suai, Tatau, Sebauh, Bintulu",
    "Sibu, Mukah, Dalat, Song, Igan, Oya, Balingian, Kanowit, Kapit",
    "Sarikei, Matu, Julau, Rajang, Daro, Bintangor, Belawai",
    "Lubok Antu, Sri Aman, Roban, Debak, Kabong, Lingga, Engkelili, Betong, Spaoh, Pusa, Saratok",
    "Serian, Simunjan, Samarahan, Sebuyau, Meludam",
    "Kuching, Bau, Lundu, Sematan",
    "Zon Khas (Kampung Patarikan)",
    "Kuala Terengganu, Marang, Kuala Nerus",
    "Besut, Setiu",
    "Hulu Terengganu",
    "Dungun, Kemaman",
    "Kuala Lumpur, Putrajaya",
    "Labuan",
  }

  @(static)
  selected: int = 0

  if imgui.begin_combo("Zones", zones_name[selected]) {
    for item, idx in zones_name {
      is_selected := selected == idx
      if imgui.selectable(item, false) do selected = idx
      if is_selected do imgui.set_item_default_focus()
    }

    defer imgui.end_combo()
  }

  @(static)
  clicked: int = 0
  imgui.same_line()

  if ok := imgui.button("Fetch", imgui.Vec2{60, 30}); ok {
    clicked += 1
  }

  @(static)
  prayer: Prayer

  if clicked & 1 == 1 {
    prayer = fetch_prayers(zones_code[selected])
    clicked += 1
  }

  @(static)
  current_day: int
  current_day = time.day(time.now())

  imgui.begin_table("prayer_table", 8, imgui.Table_Flags.RowBg | imgui.Table_Flags.Borders | imgui.Table_Flags.SizingStretchSame)

  imgui.table_setup_column("Date")
  imgui.table_setup_column("Imsak")
  imgui.table_setup_column("Subuh")
  imgui.table_setup_column("Syuruk")
  imgui.table_setup_column("Zohor")
  imgui.table_setup_column("Asar")
  imgui.table_setup_column("Maghrib")
  imgui.table_setup_column("Isya")
  imgui.table_headers_row()

  for i := 0; i < len(prayer.PrayerTime); i += 1 {
    imgui.table_next_row()
    pt := prayer.PrayerTime[i]
    color := i + 1 == current_day ? imgui.Vec4{0.1, 0.7, 0, 1} : imgui.Vec4{0, 0, 0, 1}


    imgui.table_set_column_index(0)
    imgui.text_colored(color, pt.Date)

    imgui.table_set_column_index(1)
    imgui.text_colored(color, pt.Imsak)

    imgui.table_set_column_index(2)
    imgui.text_colored(color, pt.Fajr)

    imgui.table_set_column_index(3)
    imgui.text_colored(color, pt.Syuruk)

    imgui.table_set_column_index(4)
    imgui.text_colored(color, pt.Dhuhr)

    imgui.table_set_column_index(5)
    imgui.text_colored(color, pt.Asr)

    imgui.table_set_column_index(6)
    imgui.text_colored(color, pt.Maghrib)

    imgui.table_set_column_index(7)
    imgui.text_colored(color, pt.Isha)
  }

  imgui.end_table()

  imgui.end()
}

is_key_down :: proc(e: sdl.Event, sc: sdl.Scancode) -> bool {
  return e.key.type == .KEYDOWN && e.key.keysym.scancode == sc
}

init_imgui_state :: proc(window: ^sdl.Window) -> Imgui_State {
  using res := Imgui_State{}

  imgui.create_context()
  imgui.style_colors_light()

  imsdl.setup_state(&res.sdl_state)
  imgl.setup_state(&res.opengl_state)

  return res
}

imgui_new_frame :: proc(window: ^sdl.Window, state: ^Imgui_State) {
  imsdl.update_display_size(window)
  imsdl.update_mouse(&state.sdl_state, window)
  imsdl.update_dt(&state.sdl_state)
}

write_callback :: proc "c" (ptr: [^]byte, size, nmemb: c.size_t, data: ^rawptr) -> c.size_t {
  context = runtime.default_context()

  realsize := size * nmemb
  SIZE = realsize
  data^ = mem.resize(data^, 1, cast(int)realsize + 1)
  mem.copy(data^, ptr, cast(int)realsize)

  _data := cast([^]byte)data^
  _data[realsize] = 0

  return realsize
}

fetch_prayers :: proc(zone: string) -> Prayer {
  data: rawptr = mem.alloc(1)

  url: string

  switch zone {
  case "DEFLT":
    url, _ = strings.concatenate({API, DEFAULT_ZONE})
  case:
    url, _ = strings.concatenate({API, zone})
  }

  curl := ocurl.init()
  defer ocurl.cleanup(curl)

  ocurl.setopt(curl, ocurl.CurlOption.URL, url)
  ocurl.setopt(curl, ocurl.CurlOption.Httpget, 1)
  ocurl.setopt(curl, ocurl.CurlOption.Writedata, &data)
  ocurl.setopt(curl, ocurl.CurlOption.Writefunction, write_callback)

  imgui.same_line()
  imgui.text("Fetching data from Jakim...")

  if res := ocurl.perform(curl); res != ocurl.CurlCode.Ok {
    imgui.same_line()
    imgui.text("Fetching data from Jakim...")
  }

  response := (cast([^]byte)data)[:SIZE]

  prayer := Prayer{}
  json.unmarshal(response, &prayer)

  //probably need to cleanup prayer var
  return prayer
}
