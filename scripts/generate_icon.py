#!/usr/bin/env python3
"""Generate Moments app icon - dark gradient with stylized photo frames and sparkles"""

from PIL import Image, ImageDraw
import math

def create_gradient(size, colors):
    """Create a diagonal gradient"""
    img = Image.new('RGBA', (size, size))
    draw = ImageDraw.Draw(img)
    
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * size)
            if t < 0.5:
                t2 = t * 2
                r = int(colors[0][0] * (1 - t2) + colors[1][0] * t2)
                g = int(colors[0][1] * (1 - t2) + colors[1][1] * t2)
                b = int(colors[0][2] * (1 - t2) + colors[1][2] * t2)
            else:
                t2 = (t - 0.5) * 2
                r = int(colors[1][0] * (1 - t2) + colors[2][0] * t2)
                g = int(colors[1][1] * (1 - t2) + colors[2][1] * t2)
                b = int(colors[1][2] * (1 - t2) + colors[2][2] * t2)
            draw.point((x, y), fill=(r, g, b, 255))
    
    return img

def draw_rounded_rect(draw, xy, radius, fill=None, outline=None, width=1):
    """Draw a rounded rectangle"""
    x1, y1, x2, y2 = xy
    diameter = radius * 2
    
    draw.ellipse([x1, y1, x1 + diameter, y1 + diameter], fill=fill, outline=outline, width=width)
    draw.ellipse([x2 - diameter, y1, x2, y1 + diameter], fill=fill, outline=outline, width=width)
    draw.ellipse([x1, y2 - diameter, x1 + diameter, y2], fill=fill, outline=outline, width=width)
    draw.ellipse([x2 - diameter, y2 - diameter, x2, y2], fill=fill, outline=outline, width=width)
    
    draw.rectangle([x1 + radius, y1, x2 - radius, y2], fill=fill)
    draw.rectangle([x1, y1 + radius, x2, y2 - radius], fill=fill)

def draw_sparkle(draw, center, size, color):
    """Draw a 4-point star/sparkle"""
    cx, cy = center
    points = []
    num_points = 8
    
    for i in range(num_points):
        angle = i * (2 * math.pi / num_points) - math.pi / 2
        if i % 2 == 0:
            r = size
        else:
            r = size * 0.3
        x = cx + r * math.cos(angle)
        y = cy + r * math.sin(angle)
        points.append((x, y))
    
    draw.polygon(points, fill=color)

def generate_app_icon(size=1024):
    """Generate the app icon"""
    dark_colors = [
        (20, 20, 30),
        (30, 25, 50),
        (12, 12, 25)
    ]
    img = create_gradient(size, dark_colors)
    draw = ImageDraw.Draw(img, 'RGBA')
    
    center_x, center_y = size // 2, size // 2
    glow_radius = int(size * 0.4)
    for r in range(glow_radius, 0, -5):
        alpha = int(30 * (1 - r / glow_radius))
        draw.ellipse(
            [center_x - r, center_y - r, center_x + r, center_y + r],
            fill=(100, 80, 180, alpha)
        )
    
    frame_size = int(size * 0.5)
    frame_x = (size - frame_size) // 2 - 40
    frame_y = (size - frame_size) // 2 - 40
    corner_radius = 60
    
    draw_rounded_rect(
        draw,
        [frame_x, frame_y, frame_x + frame_size, frame_y + frame_size],
        corner_radius,
        fill=(50, 40, 90, 200)
    )
    
    draw_rounded_rect(
        draw,
        [frame_x + 3, frame_y + 3, frame_x + frame_size - 3, frame_y + frame_size - 3],
        corner_radius - 2,
        outline=(130, 100, 200, 180),
        width=4
    )
    
    frame2_size = int(size * 0.45)
    frame2_x = (size - frame2_size) // 2 + 50
    frame2_y = (size - frame2_size) // 2 + 50
    
    draw_rounded_rect(
        draw,
        [frame2_x, frame2_y, frame2_x + frame2_size, frame2_y + frame2_size],
        int(corner_radius * 0.9),
        fill=(40, 30, 70, 230)
    )
    
    draw_rounded_rect(
        draw,
        [frame2_x + 2, frame2_y + 2, frame2_x + frame2_size - 2, frame2_y + frame2_size - 2],
        int(corner_radius * 0.9) - 2,
        outline=(150, 120, 220, 200),
        width=3
    )
    
    draw_sparkle(draw, (int(size * 0.75), int(size * 0.25)), 80, (255, 230, 130, 255))
    draw_sparkle(draw, (int(size * 0.85), int(size * 0.38)), 35, (230, 210, 255, 200))
    draw_sparkle(draw, (int(size * 0.20), int(size * 0.78)), 45, (180, 160, 255, 180))
    draw_sparkle(draw, (int(size * 0.68), int(size * 0.15)), 25, (255, 255, 200, 150))
    
    return img

if __name__ == "__main__":
    import sys
    output = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.png"
    
    icon = generate_app_icon(1024)
    icon.save(output, "PNG")
    print(f"Generated: {output}")
