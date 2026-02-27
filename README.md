## Inspiration

“Where did I put my keys?” “Who is this person?” “What was I doing a moment ago?” Over 55 million people worldwide live with dementia, and millions more elderly adults struggle with memory, safety, and independence. The rapidly growing development in wearable technology inspired us to think about how spatial computing can be applied to tackle the problems that the elderly face today. Our curiosity led us to build Clove, an AI-powered augmented reality application to help elders recall information, recognize loved ones, and stay safe through real-time support. 

## What it does

1. 🧠 **Contextual memory recall:** Clove continually captures and indexes daily experiences. Simply ask a question like “Where did I put my keys” and receive instant, context-aware answers paired with a brief video clip of the exact moment—turning foggy memories into crystal-clear recall.
> ex. “Where did I put my keys?”, “Did I turn the stove off?”

2. 👤 **Identity recognition overlays:** Puts names to important faces. Our AR nametags instantly identify loved ones, caregivers, and frequent visitors, displaying their name and relationship in your field of view. Add contacts with cherished photo memories, and never experience that uncomfortable moment of forgetting again.

3. 📞 **Two-way care calls:** Through Zoom-powered video calls, family members, doctors, and caregivers can see exactly what you see and connect with you in real-time, from taking medication to cooking a meal.
> ex. “Call my daughter", “Start a Zoom call”

4. 📋 **Task manager and reminders:** Caregivers and family members can create personalized reminders for important tasks, such as taking the right medications on time. The system proactively notifies users at the right time with clear, step-by-step guidance, and confirms completion back to caregivers.
> ex. Check “take Wednesday meds” off my list

5. 🚨 **Instant fall detection & alerts:** Help arrives before you ask. Motion sensors detect hard falls immediately and automatically notifies emergency contacts with your precise location. Give both users and families the peace of mind they deserve.

6. 📊 **Weekly cognitive reports:** After each Zoom call, the app uploads the meeting transcript to a PostgreSQL database on Render. A weekly cron job analyzes all conversations and generates a cognitive health report. The report emails to a caregiver with insights about the user's mental health. Analysis includes:  cognitive scores, mood patterns, areas of concern and strength, and more.

## How we built it

We built a native iOS app in Swift/SwiftUI leveraging a combination of on-device Apple frameworks and cloud APIs to power each core feature, with the goal of shipping in the future to devices like Meta Ray-Bans.

- **Contextual memory recall:** The app continuously records rolling 6-second video clips with AVFoundation and indexes them on-device using Vision (scene/text labels) and Natural Language (sentence embeddings) for semantic search. OpenAI GPT-4o-mini improves clip descriptions. Voice input is handled by the Speech framework; we embed the query, find the best clip, and use the OpenAI API to generate a one-sentence answer, then play the clip and speak the answer with TTS.
- **Identity recognition overlays:** Contacts are stored with face embeddings from Vision (landmarks). At runtime we detect faces in the AR feed, match them to stored embeddings, and show name and relationship above the person in the AR view.
- **Two-way care calls:** We integrated the Zoom Video SDK for real-time video calls with transcript capture, and the VAPI voice AI platform for outbound phone calls. Both are accessible hands-free through our voice assistant—users simply say "call my daughter" or "start a Zoom call," and the assistant resolves the contact and initiates the session via OpenAI function calling.
- **Instant fall detection & alerts:** We monitor the device accelerometer via CoreMotion and apply a fall detection algorithm that triggers a VAPI-powered emergency call to a pre-configured caregiver and pushes a critical local notification, all with a 10-second cooldown to prevent false re-triggers.
- *Universal voice assistant:** We use OpenAI function calling so voice commands can trigger search_memories, Zoom (Zoom Video SDK), or call_contact (VAPI). A shared AppSpeechManager speaks confirmations and errors.
- **Weekly cognitive reports:** Each Zoom call transcript is automatically stored in a PostgreSQL database hosted on Render. A weekly cron job aggregates the past week's conversations and sends them to OpenAI for analysis, generating cognitive health scores (clarity, coherence, memory recall), mood patterns, and conversation statistics like total calls and duration. The resulting report is emailed to caregivers via Resend, flagging any concerning patterns that may need attention.

## Challenges we ran into
- **Adapting AR glasses-inspired vision for mobile form factor:** Translating AR glasses interactions to mobile devices required reimagining our approach to UX while conveying the original potential for real in-glasses deployment. AR glasses offer hands-free, persistent overlays in the user's natural field of view, while mobile devices demand active engagement and screen-based interfaces. We solved this by developing a hybrid interaction model that maintains spatial awareness on mobile through camera-based AR, while designing for future scalability to dedicated wearable hardware.
- **Real-time facial recognition accuracy:** Achieving reliable facial recognition for elderly users presented unique obstacles—varied lighting conditions, users with glasses or changing appearances, and the need to avoid false positives that could cause confusion.
- **Efficient storage and semantic search:** Continuously recording and storing video clips would quickly become storage-prohibitive and computationally expensive. Our solution combines intelligent scene detection to capture only meaningful moments and an embedding system that converts video content into searchable vector representations, enabling natural language queries to surface relevant clips in milliseconds rather than hours

## What we learned
- 🫂 **Empathy through design.** This experience pushed me to build for people whose daily challenges I don’t face myself. Designing for elderly users involves recognizing the real consequences when technology fails someone who depends on it. *- Linkai*
- ⚖️ **Technical trade-offs.** I learned a lot about the technical trade-offs between speed and quality while working on this project. More frequent calls to GPT-4o mini would lead to higher quality memory recalls but would slow down performance noticeably. It was really important to find the right balance between the two. *- Dylan*
- 💡 **Narrowing down ideas.** This hackathon taught me to be specific and always have the end-user in mind. What do they want? What do they need? It is common for developers to build features that receive little appreciation from the public, which further emphasizes the need to think critically about the product at every step. *- Kevin*
- ⚙️ **Exposure to new tools/techniques.** This hackathon exposed me to feature mapping and how to use it for facial recognition. Also received exposure on how to integrate tools like Render into our project to automate sending emails that contain a summary of the user's actions and store user data. *- Will*

## What's next for Clove
While our current prototype runs on mobile devices, our vision from day one has been deployment on dedicated AR glasses. The mobile version proves the concept, but the real magic happens when this technology lives naturally in a user's field of view: hands-free, always accessible, and truly seamless. As devices like Meta's Ray-Ban smart glasses and Apple's Vision products mature and become more affordable, we'll be ready to transition our platform to true wearable form.
