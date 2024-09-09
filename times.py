import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
CSV_PATH = "times.csv"
df = pd.read_csv(CSV_PATH)
df = df[["Frame_End_Render_GetTexture","Frame_End_Render_EncodeCommands", "Frame_End_Render_QueueSubmit", "Frame_End_Render_Present"]]
df = df[:200]
df.plot(kind='bar', stacked=True, figsize=(20, 10))
plt.xticks([])
plt.ylabel('Time in ms')
plt.xlabel('Frame')
plt.show()