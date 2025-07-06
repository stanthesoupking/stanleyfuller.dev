package main

import "base:sanitizer"
import "core:c"
import "vendor:stb/image"
import os "core:os/os2"
import "core:fmt"
import "core:strings"
import "core:math"
import "core:strconv"
import "core:encoding/uuid"
import "core:crypto/sha2"
import "core:io"

THUMBNAIL_MAX_DIMENSION :: 768

Site :: struct {
    albums: []Album
}

Species :: enum {
    None,
    Scarlet_Robin,
    Grey_Currawong
}

species_get_name :: proc(v: Species) -> string {
    switch v {
        case .None: return ""
        case .Scarlet_Robin: return "Scarlet Robin"
        case .Grey_Currawong: return "Grey Currawong"
    }
    return "?"
}

species_get_latin_name :: proc(v: Species) -> string {
    switch v {
        case .None: return ""
        case .Scarlet_Robin: return "Petroica Boodang"
        case .Grey_Currawong: return "Strepera Versicolor"
    }
    return "?"
}

Month :: enum u8 {
    January,
    February,
    March,
    April,
    May,
    June,
    July,
    August,
    September,
    October,
    November,
    December
}

Date_Time :: struct {
    day: u8,
    month: Month,
    year: u16
}

month_to_string :: proc(month: Month) -> string {
    switch month {
        case .January: return "January"
        case .February: return "February"
        case .March: return "March"
        case .April: return "April"
        case .May: return "May"
        case .June: return "June"
        case .July: return "July"
        case .August: return "August"
        case .September: return "September"
        case .October: return "October"
        case .November: return "November"
        case .December: return "December"
    }
    return "?"
}

int_to_string :: proc(v: int) -> string {
    buf: [16]byte
    return strings.clone(strconv.itoa(buf[:], v))
}

date_time_to_string :: proc(dt: Date_Time) -> string {
    day_s := int_to_string(int(dt.day))
    month_s := month_to_string(dt.month)
    year_s := int_to_string(int(int(dt.year)))
    return strings.concatenate({ day_s, " ", month_s, " ", year_s })
}

Photo :: struct {
    name: string,
    path: string,
    date: Date_Time,
    location: string,
    alt_text: string,
    film_stock: Maybe(string),
    species: Species,
    thumbnail_path: Maybe(string),
    page_path: Maybe(string),
    thumbnail_size: [2]int
}

Album :: struct {
    name: string,
    photos: []Photo
}

site := Site {
    albums = {
        {
            name = "Wildlife",
            photos = {
                {
                    path = "public/photos/IMG_0997.jpg",
                    date = { 5, .July, 2025 },
                    location = "Mount Nelson, Tasmania",
                    alt_text = "A scarlet robin perched on the branch of a gum tree.",
                    species = .Scarlet_Robin
                },
                {
                    path = "public/photos/IMG_1030.jpg",
                    date = { 5, .July, 2025 },
                    location = "Mount Nelson, Tasmania",
                    alt_text = "A scarlet robin taking off from a branch.",
                    species = .Scarlet_Robin
                },
                {
                    path = "public/photos/IMG_1116.jpg",
                    date = { 5, .July, 2025 },
                    location = "Mount Nelson, Tasmania",
                    alt_text = "A scarlet robin with a bug in mouth.",
                    species = .Scarlet_Robin
                },
                {
                    path = "public/photos/IMG_1073.jpg",
                    date = { 5, .July, 2025 },
                    location = "Mount Nelson, Tasmania",
                    alt_text = "A grey currawong perched on the branch of a gum tree.",
                    species = .Grey_Currawong
                },
            }
        },
        {
            name = "Landscape",
            photos = {
                {
                    path = "public/photos/IMG_5076.jpg",
                    date = { 23, .August, 2024 },
                    location = "The Needles, Tasmania",
                    alt_text = "Mountains with sun peeking through clouds.",
                    film_stock = "Kodak Gold 200"
                },
                {
                    path = "public/photos/IMG_5077.jpg",
                    date = { 23, .August, 2024 },
                    location = "The Needles, Tasmania",
                    alt_text = "Mountains with sun peeking through clouds.",
                    film_stock = "Kodak Gold 200"
                },
            }
        }
    }
}

Generator_Context :: struct {
    site: ^Site,
    output_path: string
}

to_site_path :: proc(ctx: ^Generator_Context, path: string) -> string {
    sub := strings.substring_from(path, len(ctx.output_path) + 1) or_else panic("Failed to get site path.")
    return strings.concatenate({"/", sub})
}

to_last_component :: proc(path: string) -> string {
    start := strings.last_index(path, "/")
    end := strings.last_index(path, ".")
    return path[start:end]
}

copy_photos :: proc(ctx: ^Generator_Context, output_path: string) {
    for &album in ctx.site.albums {
        for &photo in album.photos {
            new_path := strings.concatenate({output_path, "/", to_last_component(photo.path), ".jpg"})
            os.copy_file(new_path, photo.path)
            photo.path = new_path
        }
    }
}

gen_thumbnails :: proc(ctx: ^Generator_Context) {
    thumbnails_path := strings.concatenate({ctx.output_path, "/thumbnails"})
    os.remove_all(thumbnails_path)
    os.make_directory(thumbnails_path)

    next_thumb_id := 0
    for &album in ctx.site.albums {
        for &photo in album.photos {
            img_width, img_height, img_channels: c.int
            img_bytes := image.load(strings.clone_to_cstring(photo.path), &img_width, &img_height, &img_channels, 3)
            assert(img_bytes != nil, "Failed to load image.")

            img_max_size := max(img_width, img_height)
            thumb_scale := f32(THUMBNAIL_MAX_DIMENSION) / f32(max(img_width, img_height))

            thumb_width := c.int(math.ceil(f32(img_width) * thumb_scale))
            thumb_height := c.int(math.ceil(f32(img_height) * thumb_scale))
            thumb_bytes := make([]byte, thumb_width * thumb_height * img_channels)

            image.resize(img_bytes, img_width, img_height, img_width * img_channels, raw_data(thumb_bytes), thumb_width, thumb_height, thumb_width * img_channels, .UINT8, img_channels, false, 0, .CLAMP, .CLAMP, .DEFAULT, .DEFAULT, .SRGB, nil)
            image.image_free(img_bytes)

            itoa_buf: [16]byte
            thumb_id_str := strconv.itoa(itoa_buf[:], next_thumb_id)
            next_thumb_id += 1

            thumb_path := strings.concatenate({thumbnails_path, "/", to_last_component(photo.path), "_thumbnail.jpg"})
            image.write_jpg(strings.clone_to_cstring(thumb_path), thumb_width, thumb_height, img_channels, raw_data(thumb_bytes), 90)
            photo.thumbnail_path = thumb_path
            photo.thumbnail_size = { int(thumb_width), int(thumb_height) }
        }
    }
}

write_page_head :: proc(ctx: ^Generator_Context, writer: io.Stream) {
    fmt.wprintln(writer, "<meta charset=\"UTF-8\">")
    fmt.wprintln(writer, "<head>")
    fmt.wprintln(writer, "<title>Stan's Website</title>")
    fmt.wprintln(writer, "<link href=\"/assets/style.css\" rel=\"stylesheet\">")
    fmt.wprintln(writer, "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">")
    fmt.wprintln(writer, "</head>")
}

sanitize_path_component :: proc(src: string) -> string {
    cpy := strings.clone(src)
    cpy, _ = strings.replace_all(cpy, " ", "_")
    return strings.to_lower(cpy)
}

gen_photo_page :: proc(ctx: ^Generator_Context, photo: ^Photo, output_path: string) {
    fd := os.open(output_path, {.Write, .Create}) or_else panic("Failed to write photo page.")
    writer := os.to_writer(fd)

    fmt.wprintfln(writer, "<!DOCTYPE html>")
    fmt.wprintln(writer, "<html>")
    write_page_head(ctx, writer)
    fmt.wprintln(writer, "<body>")
    fmt.wprintln(writer, "<div class=\"image-wrapper\">")
    fmt.wprintfln(writer, "<img src=\"{}\" alt=\"{}\" class=\"image-view\">", to_site_path(ctx, photo.path), photo.alt_text)
    fmt.wprintln(writer, "</div>")
    fmt.wprintln(writer, "<div class=\"image-information\">")
    fmt.wprintfln(writer, "<p>Location: {}</p>", photo.location)
    fmt.wprintfln(writer, "<p>Date: {}</p>", date_time_to_string(photo.date))
    
    film_stock, has_film_stock := photo.film_stock.?
    if has_film_stock {
        fmt.wprintfln(writer, "<p>Film: {}</p>", film_stock)
    }

    if photo.species != .None {
        fmt.wprintfln(writer, "<p>Species: {} — {}</p>", species_get_name(photo.species), species_get_latin_name(photo.species))
    }

    fmt.wprintln(writer, "</div>")

    fmt.wprintln(writer, "</body>")
    fmt.wprintln(writer, "</html>")

    os.flush(fd)
    os.close(fd)
}

gen_photo_pages :: proc(ctx: ^Generator_Context) {
    albums_path := strings.concatenate({ctx.output_path, "/albums"})
    os.remove_all(albums_path)
    os.make_directory(albums_path)

    for &album in ctx.site.albums {
        album_path := strings.concatenate({albums_path, "/", sanitize_path_component(album.name)})
        os.make_directory(album_path)

        photo_index := 0
        for &photo in album.photos {
            buf: [16]byte
            photo_index_str := strconv.itoa(buf[:], photo_index)
            photo.page_path = strings.concatenate({album_path, "/", photo_index_str, ".html"})
            gen_photo_page(ctx, &photo, photo.page_path.(string))

            photo_index += 1
        }
    }
}

gen_index_page :: proc(ctx: ^Generator_Context, output_path: string) {
    os.remove(output_path)
    fd := os.open(output_path, {.Write, .Create}) or_else panic("Failed to write index page.")
    writer := os.to_writer(fd)

    fmt.wprintfln(writer, "<!DOCTYPE html>")
    fmt.wprintln(writer, "<html>")
    write_page_head(ctx, writer)
    fmt.wprintln(writer, "<body>")
    fmt.wprintln(writer, "<div class=\"index-page\">")
    fmt.wprintln(writer, "<h1>Stanley Fuller</h1>")

    for album in ctx.site.albums {
        fmt.wprintfln(writer, "<h2>{}</h2>", album.name)
        fmt.wprintln(writer, "<div class=\"gallery\">")
        for photo in album.photos {
            fmt.wprintf(writer, "<a href=\"{}\">", to_site_path(ctx, photo.page_path.(string)))
            fmt.wprintf(writer, "<img src=\"{}\" alt=\"{}\">", to_site_path(ctx, photo.thumbnail_path.(string)), photo.alt_text)
            fmt.wprintln(writer, "</a>")
        }
        fmt.wprintln(writer, "</div>")
    }

    fmt.wprintln(writer, "</div>")
    fmt.wprintln(writer, "</body>")
    fmt.wprintln(writer, "</html>")

    os.flush(fd)
    os.close(fd)
}

gen_site :: proc(site: ^Site, output_path: string) {
    ctx := Generator_Context {
        site = site,
        output_path = output_path
    }

    gen_thumbnails(&ctx)
    gen_photo_pages(&ctx)
    gen_index_page(&ctx, strings.concatenate({output_path, "/index.html"}))
}

main :: proc() {
    fmt.println("Building site...")
    gen_site(&site, "public")
}