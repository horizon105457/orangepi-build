import cv2
import v4l2cam
import time

cam = v4l2cam.V4L2Camera("/dev/video8", 640, 480)

if not cam.init():
	print("init failed")
if not cam.start():
	print("start failed")

frame_count = 0
start_time = time.time()
fps = 0.0

while True:
	try:
		frame = cam.get_frame()
		frame_count += 1
		now = time.time()
		elapsed = now - start_time

		if elapsed >= 1.0:
			fps = frame_count / elapsed
			frame_count = 0
			start_time = now

		fps_text = f"FPS: {fps:.1f}"
		cv2.putText(frame, fps_text, (10, 30),
					cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)

		cv2.imshow("Preview", frame)

	except Exception as e:
		print("Error:", e)
		break

	if cv2.waitKey(1) & 0xFF == 27:
		break

cam.stop()
cv2.destroyAllWindows()

